from fastapi import APIRouter, Depends, HTTPException, status, Request, Response
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
import secrets
from datetime import datetime, timedelta

from app.core.database import get_db
from app.core.security import (
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
    register_failed_attempt,
    reset_login_attempts,
    hash_password,
)
from app.core.limiter import limiter
from app.core.sanitizer import sanitize_name
from app.core.audit_log import log_security_event, AuditEvent
from app.crud.user import get_user_by_email, get_user_by_id
from app.crud.revoked_token import revoke_token, is_token_revoked
from app.schemas.auth import LoginRequest, UserCreate, GuestLoginRequest, GuestCodeResponse, ConvertGuestRequest, ForgotPasswordRequest, ResetPasswordRequest, ChangePasswordRequest
from app.db.models.user import User
from app.db.models.event import Event
from app.db.models.event_participant import EventParticipant
from app.db.models.guest_code import GuestCode
from app.api.deps import get_current_user, get_current_user_allow_password_change
from app.services import password_recovery as pwd_recovery_svc
from app.core.email_service import EmailDeliveryError

router = APIRouter(prefix="/auth", tags=["Auth"])
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


def _get_ip(request: Request) -> str:
    """Extrae la IP real del cliente, considerando proxies."""
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def check_user_status(user: User, db: Session = None) -> None:
    """Verifica bloqueo temporal y flags de estado."""
    if user.lock_until and user.lock_until <= datetime.utcnow():
        user.is_locked = False
        user.lock_until = None
        if db:
            db.commit()

    if user.is_locked:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cuenta bloqueada temporalmente",
        )
    if user.must_change_password:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Debes cambiar tu contraseña antes de continuar",
        )


@router.post("/register", status_code=status.HTTP_201_CREATED)
@limiter.limit("5/minute")
def register(request: Request, response: Response, user_data: UserCreate, db: Session = Depends(get_db)):
    from app.crud.user import create_user
    from app.db.models.user import UserRole

    ip = _get_ip(request)

    existing = get_user_by_email(db, user_data.email)
    if existing:
        # No revelar si el email existe — respuesta genérica
        log_security_event(
            AuditEvent.REGISTER,
            ip=ip,
            email=user_data.email,
            detail="Intento de registro con email duplicado",
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No se pudo completar el registro",
        )

    hashed = hash_password(user_data.password)
    new_user = create_user(db, {
        "email": user_data.email,
        "hashed_password": hashed,
        "name": sanitize_name(user_data.name),
        "phone": user_data.phone,
        "role": UserRole.organizer if user_data.is_organizer else UserRole.user,
    })

    log_security_event(
        AuditEvent.REGISTER,
        ip=ip,
        user_id=str(new_user.id),
        email=user_data.email,
        detail=f"role={'organizer' if user_data.is_organizer else 'user'}",
    )

    return {"message": "Usuario registrado correctamente", "user_id": str(new_user.id)}


@router.post("/login")
@limiter.limit("10/minute")
def login(request: Request, response: Response, login_data: LoginRequest, db: Session = Depends(get_db)):
    ip = _get_ip(request)
    user = get_user_by_email(db, login_data.email)

    # Respuesta genérica para no revelar si el email existe (anti-enumeración)
    _INVALID_CREDS = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Credenciales inválidas",
        headers={"WWW-Authenticate": "Bearer"},
    )

    if not user:
        # Ejecutar verify_password con hash dummy para tiempo constante
        verify_password(login_data.password, hash_password(secrets.token_hex(16)))
        log_security_event(
            AuditEvent.LOGIN_FAILED,
            ip=ip,
            email=login_data.email,
            detail="Usuario no encontrado",
        )
        raise _INVALID_CREDS

    # Verificar bloqueo antes de comprobar contraseña
    if user.lock_until and user.lock_until <= datetime.utcnow():
        user.is_locked = False
        user.lock_until = None
        db.commit()

    if user.is_locked:
        log_security_event(
            AuditEvent.LOGIN_BLOCKED,
            ip=ip,
            user_id=str(user.id),
            email=user.email,
            detail=f"Bloqueado hasta {user.lock_until}",
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cuenta bloqueada temporalmente",
        )

    if user.must_change_password:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Debes cambiar tu contraseña antes de continuar",
        )

    if not verify_password(login_data.password, user.hashed_password):
        register_failed_attempt(user, db)
        log_security_event(
            AuditEvent.LOGIN_FAILED,
            ip=ip,
            user_id=str(user.id),
            email=user.email,
            detail=f"Intento {user.failed_login_attempts}",
        )
        raise _INVALID_CREDS

    reset_login_attempts(user, db)

    access_token = create_access_token(str(user.id), user.email)
    refresh_token = create_refresh_token(str(user.id), user.email)

    log_security_event(
        AuditEvent.LOGIN_SUCCESS,
        ip=ip,
        user_id=str(user.id),
        email=user.email,
    )

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }


@router.post("/refresh")
@limiter.limit("20/minute")
def refresh(
    request: Request,
    response: Response,
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
):
    ip = _get_ip(request)
    payload = decode_token(token)

    if payload.get("type") != "refresh":
        log_security_event(AuditEvent.INVALID_TOKEN, ip=ip, detail="Tipo de token incorrecto en /refresh")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Se requiere un refresh token",
        )

    jti = payload.get("jti")
    if jti and is_token_revoked(db, jti):
        log_security_event(AuditEvent.INVALID_TOKEN, ip=ip, detail="Refresh token ya revocado — posible replay attack")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token revocado",
        )

    user = get_user_by_id(db, payload["sub"])
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Usuario no encontrado")

    check_user_status(user, db)

    new_access = create_access_token(str(user.id), user.email)
    new_refresh = create_refresh_token(str(user.id), user.email)

    if jti:
        revoke_token(jti, db)

    log_security_event(AuditEvent.TOKEN_REFRESH, ip=ip, user_id=str(user.id))

    return {
        "access_token": new_access,
        "refresh_token": new_refresh,
        "token_type": "bearer",
    }


@router.post("/logout", status_code=status.HTTP_200_OK)
def logout(
    request: Request,
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
):
    ip = _get_ip(request)
    payload = decode_token(token)
    jti = payload.get("jti")
    user_id = payload.get("sub")

    if jti and not is_token_revoked(db, jti):
        revoke_token(jti, db)

    log_security_event(AuditEvent.LOGOUT, ip=ip, user_id=user_id)
    return {"message": "Sesión cerrada correctamente"}


# ---------------------------------------------------------
# Acceso como invitado
# ---------------------------------------------------------

def _generate_unique_code(db: Session) -> str:
    """Genera un código numérico de 6 dígitos único usando secrets (CSPRNG)."""
    for _ in range(10):
        # secrets.randbelow es criptográficamente seguro
        code = f"{secrets.randbelow(1_000_000):06d}"
        if not db.query(GuestCode).filter(GuestCode.code == code).first():
            return code
    raise HTTPException(status_code=500, detail="No se pudo generar un código único")


@router.post("/guest-login", status_code=status.HTTP_200_OK)
@limiter.limit("10/minute")
def guest_login(request: Request, response: Response, data: GuestLoginRequest, db: Session = Depends(get_db)):
    ip = _get_ip(request)
    guest_code = db.query(GuestCode).filter(GuestCode.code == data.code).first()

    if not guest_code or not guest_code.is_valid():
        log_security_event(AuditEvent.GUEST_LOGIN, ip=ip, detail=f"Código inválido: {data.code}")
        raise HTTPException(status_code=404, detail="Código inválido o expirado")

    event = db.query(Event).filter(Event.id == guest_code.event_id).first()
    if not event or not event.is_active:
        raise HTTPException(status_code=403, detail="El evento no está disponible")

    current_count = db.query(EventParticipant).filter(
        EventParticipant.event_id == event.id,
        EventParticipant.is_active == True,
    ).with_for_update().count()
    if current_count >= event.max_participants:
        raise HTTPException(status_code=403, detail="El evento está lleno")

    guest_number = guest_code.used_count + 1
    guest_name = f"Invitado {guest_number}"
    guest_email = f"guest_{guest_code.code}_{guest_number}@festisafe.internal"
    # Contraseña temporal con entropía criptográfica
    temp_password = hash_password(secrets.token_urlsafe(32))

    guest_user = User(
        name=guest_name,
        email=guest_email,
        hashed_password=temp_password,
        is_guest=True,
    )
    db.add(guest_user)
    db.flush()

    participant = EventParticipant(event_id=event.id, user_id=guest_user.id)
    db.add(participant)

    guest_code.used_count += 1
    if guest_code.remaining_uses == 0:
        guest_code.is_active = False

    db.commit()
    db.refresh(guest_user)

    access_token = create_access_token(str(guest_user.id), guest_user.email)
    refresh_token = create_refresh_token(str(guest_user.id), guest_user.email)

    log_security_event(
        AuditEvent.GUEST_LOGIN,
        ip=ip,
        user_id=str(guest_user.id),
        detail=f"event_id={event.id}",
    )

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "event_id": str(event.id),
        "guest_name": guest_user.name,
        "is_guest": True,
    }


@router.post("/forgot-password", status_code=status.HTTP_200_OK)
@limiter.limit("3/minute")
def forgot_password(
    request: Request,
    response: Response,
    data: ForgotPasswordRequest,
    db: Session = Depends(get_db),
):
    """
    Inicia el flujo de recuperación de contraseña.
    Genera un token seguro, lo almacena (hash SHA-256) y lo envía por email.
    Respuesta genérica para no revelar si el email existe.
    """
    ip = _get_ip(request)
    try:
        pwd_recovery_svc.request_password_recovery(db, data.email, ip)
    except EmailDeliveryError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No se pudo enviar el email de recuperación. Inténtalo más tarde.",
        )
    return {"message": "Si el email existe, recibirás instrucciones para recuperar tu contraseña."}


@router.post("/reset-password", status_code=status.HTTP_200_OK)
@limiter.limit("10/minute")
def reset_password(
    request: Request,
    response: Response,
    data: ResetPasswordRequest,
    db: Session = Depends(get_db),
):
    """Valida el token de recuperación y establece la nueva contraseña."""
    ip = _get_ip(request)
    pwd_recovery_svc.reset_password(db, data.token, data.new_password, ip)
    return {"message": "Contraseña restablecida correctamente. Ya puedes iniciar sesión."}


@router.post("/change-password", status_code=status.HTTP_200_OK)
def change_password(
    request: Request,
    data: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user_allow_password_change),
):
    """Cambia la contraseña de un usuario autenticado (incluye flujo must_change_password)."""
    ip = _get_ip(request)
    pwd_recovery_svc.change_password(db, current_user, data.current_password, data.new_password, ip)
    return {"message": "Contraseña actualizada correctamente."}


@router.post("/convert-guest", status_code=status.HTTP_200_OK)
def convert_guest(
    data: ConvertGuestRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.core.validators import validate_password

    if not current_user.is_guest:
        raise HTTPException(status_code=400, detail="La cuenta ya es permanente")

    existing = get_user_by_email(db, data.email)
    if existing and existing.id != current_user.id:
        raise HTTPException(status_code=400, detail="No se pudo completar la conversión")

    validate_password(data.password)

    current_user.email = data.email
    current_user.hashed_password = hash_password(data.password)
    current_user.phone = data.phone
    current_user.is_guest = False
    current_user.password_changed_at = datetime.utcnow()

    db.commit()
    db.refresh(current_user)

    return {"message": "Cuenta convertida correctamente", "user_id": str(current_user.id)}
