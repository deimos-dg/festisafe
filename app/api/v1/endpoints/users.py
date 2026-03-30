from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime

from app.api.deps import get_current_user, get_current_active_user, require_roles, get_current_user_allow_password_change
from app.db.session import get_db
from app.db.models.user import User, UserRole
from app.db.models.device_token import DeviceToken
from app.core.security import verify_password, hash_password
from app.core.validators import validate_password
from app.core.sanitizer import sanitize_name
from app.core.audit_log import log_security_event, AuditEvent
from app.schemas.user import UserResponse, UserPublicResponse, UserUpdate, ChangePasswordRequest, FcmTokenRequest

router = APIRouter(prefix="/users", tags=["Users"])


@router.get("/me", response_model=UserResponse)
def get_me(current_user: User = Depends(get_current_active_user)):
    return current_user


@router.patch("/me", response_model=UserResponse)
def update_me(
    data: UserUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Actualiza nombre y/o teléfono del usuario."""
    if data.name is not None:
        current_user.name = sanitize_name(data.name)
    if data.phone is not None:
        current_user.phone = data.phone
    db.commit()
    db.refresh(current_user)
    return current_user


@router.post("/me/change-password", status_code=status.HTTP_200_OK)
def change_password(
    data: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user_allow_password_change),
):
    """
    Cambia la contraseña. También resuelve must_change_password.
    Usa get_current_user_allow_password_change para no bloquear si must_change_password=True.
    """
    if not verify_password(data.current_password, current_user.hashed_password):
        raise HTTPException(status_code=400, detail="Contraseña actual incorrecta")

    if data.current_password == data.new_password:
        raise HTTPException(status_code=400, detail="La nueva contraseña debe ser diferente")

    try:
        validate_password(data.new_password)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    current_user.hashed_password = hash_password(data.new_password)
    current_user.must_change_password = False
    current_user.password_changed_at = datetime.utcnow()
    current_user.failed_login_attempts = 0
    current_user.is_locked = False
    current_user.lock_until = None
    db.commit()

    log_security_event(
        AuditEvent.PASSWORD_CHANGED,
        user_id=str(current_user.id),
        email=current_user.email,
    )
    return {"message": "Contraseña actualizada correctamente"}


@router.post("/me/become-organizer", response_model=UserResponse)
def become_organizer(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Permite a cualquier usuario activo auto-promovarse a organizador."""
    if current_user.role == UserRole.admin:
        raise HTTPException(status_code=400, detail="Ya eres administrador")
    if current_user.role == UserRole.organizer:
        raise HTTPException(status_code=400, detail="Ya eres organizador")
    current_user.role = UserRole.organizer
    db.commit()
    db.refresh(current_user)
    return current_user


@router.get("/{user_id}", response_model=UserPublicResponse)
def get_user_profile(
    user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Devuelve el perfil público de un usuario por ID. Solo nombre y rol."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return user


@router.patch("/{user_id}/role", response_model=UserResponse)
def change_user_role(
    user_id: str,
    role: UserRole,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(["admin"])),
):
    """Cambia el rol de un usuario. Solo admins."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    if str(user.id) == str(current_user.id):
        raise HTTPException(status_code=400, detail="No puedes cambiar tu propio rol")

    user.role = role
    db.commit()
    db.refresh(user)
    return user


@router.post("/me/fcm-token", status_code=status.HTTP_200_OK)
def register_fcm_token(
    data: FcmTokenRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """
    Registra o actualiza el token FCM del dispositivo del usuario.
    Si el token ya existe para otro usuario, lo reasigna al actual.
    """
    token = data.token.strip()
    if not token:
        raise HTTPException(status_code=400, detail="Token inválido")

    # Buscar si el token ya existe (puede ser de otro usuario o del mismo)
    existing = db.query(DeviceToken).filter(DeviceToken.token == token).first()
    if existing:
        # Reasignar al usuario actual (el dispositivo cambió de cuenta)
        existing.user_id = current_user.id
        existing.platform = data.platform
        existing.updated_at = datetime.utcnow()
    else:
        db.add(DeviceToken(
            user_id=current_user.id,
            token=token,
            platform=data.platform,
        ))

    db.commit()
    return {"message": "Token registrado correctamente"}


@router.delete("/me/fcm-token", status_code=status.HTTP_200_OK)
def delete_fcm_token(
    data: FcmTokenRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Elimina el token FCM al hacer logout para dejar de recibir notificaciones."""
    db.query(DeviceToken).filter(
        DeviceToken.token == data.token,
        DeviceToken.user_id == current_user.id,
    ).delete()
    db.commit()
    return {"message": "Token eliminado correctamente"}


@router.delete("/me", status_code=status.HTTP_200_OK)
def delete_my_account(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """
    Elimina la cuenta del usuario y todos sus datos asociados (GDPR).
    Elimina: participaciones en eventos, membresías de grupos,
    tokens FCM, ubicaciones y la cuenta en sí.
    """
    # SQLAlchemy cascade elimina automáticamente los datos relacionados
    # gracias a los cascade="all, delete-orphan" en los modelos
    db.delete(current_user)
    db.commit()

    log_security_event(
        AuditEvent.LOGOUT,
        user_id=str(current_user.id),
        email=current_user.email,
        detail="Cuenta eliminada por el usuario (GDPR)",
    )
    return {"message": "Cuenta eliminada correctamente"}
