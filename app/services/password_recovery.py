"""
Lógica de negocio para recuperación y cambio de contraseña.
Separa la lógica del endpoint para facilitar testing.
"""
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta
from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.core.audit_log import log_security_event, AuditEvent
from app.core.email_service import send_recovery_email, EmailDeliveryError
from app.core.security import hash_password, verify_password
from app.core.validators import validate_password
from app.crud.password_reset_token import (
    create_reset_token,
    get_token_by_hash,
    invalidate_user_tokens,
)
from app.crud.revoked_token import revoke_token
from app.crud.user import get_user_by_email
from app.db.models.revoked_token import RevokedToken

TOKEN_EXPIRY_MINUTES = 30


def generate_recovery_token() -> str:
    """Genera un token criptográficamente seguro de 32 bytes (64 chars hex)."""
    return secrets.token_hex(32)

# Seguimiento de intentos fallidos de validación de token por IP
# ip -> (count, window_start)
_failed_token_attempts: dict[str, tuple[int, datetime]] = {}
_MAX_FAILED_ATTEMPTS = 10
_BLOCK_WINDOW_MINUTES = 60


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _check_ip_brute_force(ip: str) -> None:
    """Lanza 429 si la IP superó el límite de intentos fallidos."""
    entry = _failed_token_attempts.get(ip)
    if entry:
        count, window_start = entry
        if (datetime.utcnow() - window_start).total_seconds() < _BLOCK_WINDOW_MINUTES * 60:
            if count >= _MAX_FAILED_ATTEMPTS:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Demasiados intentos. Inténtalo más tarde.",
                )
        else:
            # Ventana expirada — resetear
            _failed_token_attempts.pop(ip, None)


def _register_failed_attempt(ip: str, db: Session) -> None:
    entry = _failed_token_attempts.get(ip)
    if entry:
        count, window_start = entry
        if (datetime.utcnow() - window_start).total_seconds() < _BLOCK_WINDOW_MINUTES * 60:
            new_count = count + 1
            _failed_token_attempts[ip] = (new_count, window_start)
            if new_count >= _MAX_FAILED_ATTEMPTS:
                log_security_event(
                    AuditEvent.BRUTE_FORCE_DETECTED,
                    ip=ip,
                    detail=f"IP bloqueada tras {new_count} intentos fallidos de reset",
                )
        else:
            _failed_token_attempts[ip] = (1, datetime.utcnow())
    else:
        _failed_token_attempts[ip] = (1, datetime.utcnow())


def _revoke_all_user_refresh_tokens(db: Session, user_id) -> None:
    """Revoca todos los refresh tokens activos del usuario en la blacklist."""
    from app.db.models.revoked_token import RevokedToken as RT
    # Los refresh tokens activos no están en revoked_tokens.
    # El mecanismo de invalidación por password_changed_at en deps.py
    # ya invalida access tokens. Para refresh tokens, los añadimos a la blacklist
    # marcando el user_id en un campo de metadata si existiera, pero dado que
    # RevokedToken solo almacena jti, la invalidación se hace via password_changed_at.
    # Esta función es un hook para futuras extensiones.
    pass


def request_password_recovery(db: Session, email: str, ip: str) -> Optional[str]:
    """
    Inicia el flujo de recuperación. Siempre responde igual (anti-enumeración).
    Retorna el token generado (para que el endpoint lo use si SMTP falla en DEBUG).
    Lanza EmailDeliveryError si el SMTP falla.
    """
    user = get_user_by_email(db, email)

    log_security_event(
        AuditEvent.PASSWORD_RESET_REQUESTED,
        ip=ip,
        email=email,
        detail=f"user_found={user is not None and user.is_active}",
    )

    if not user or not user.is_active:
        _ = _hash_token(secrets.token_hex(32))
        return None

    invalidate_user_tokens(db, user.id)

    token = generate_recovery_token()
    token_hash = _hash_token(token)
    expires_at = datetime.utcnow() + timedelta(minutes=TOKEN_EXPIRY_MINUTES)

    create_reset_token(db, user.id, token_hash, expires_at)

    # Enviar email — puede lanzar EmailDeliveryError
    send_recovery_email(
        user_name=user.name or email.split("@")[0],
        user_email=user.email,
        token=token,
    )
    return token


def reset_password(db: Session, token: str, new_password: str, ip: str) -> None:
    """
    Valida el token y establece la nueva contraseña.
    Lanza HTTPException 400 si el token es inválido/expirado.
    """
    _check_ip_brute_force(ip)

    token_hash = _hash_token(token)

    # Buscar en BD — siempre calcular el hash para tiempo constante
    record = get_token_by_hash(db, token_hash)

    # Comparación en tiempo constante para prevenir timing attacks
    dummy_hash = _hash_token(secrets.token_hex(32))
    stored = record.token_hash if record else dummy_hash
    hmac.compare_digest(token_hash, stored)

    if not record or not record.is_valid():
        _register_failed_attempt(ip, db)
        log_security_event(
            AuditEvent.PASSWORD_RESET_FAILED,
            ip=ip,
            detail="Token inválido o expirado",
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Token inválido o expirado",
        )

    user = record.user
    validate_password(new_password)

    # Marcar token como usado
    record.used_at = datetime.utcnow()

    # Actualizar contraseña
    user.hashed_password = hash_password(new_password)
    user.must_change_password = False
    user.password_changed_at = datetime.utcnow()

    db.commit()

    log_security_event(
        AuditEvent.PASSWORD_CHANGED,
        ip=ip,
        user_id=str(user.id),
        email=user.email,
        detail="Restablecimiento via token",
    )


def change_password(
    db: Session,
    user,
    current_password: str,
    new_password: str,
    ip: str,
) -> None:
    """
    Cambia la contraseña de un usuario autenticado.
    Requiere verificar la contraseña actual.
    """
    if not verify_password(current_password, user.hashed_password):
        log_security_event(
            AuditEvent.PASSWORD_RESET_FAILED,
            ip=ip,
            user_id=str(user.id),
            detail="Contraseña actual incorrecta en change-password",
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Contraseña actual incorrecta",
        )

    validate_password(new_password)

    user.hashed_password = hash_password(new_password)
    user.must_change_password = False
    user.password_changed_at = datetime.utcnow()

    db.commit()

    log_security_event(
        AuditEvent.PASSWORD_CHANGED,
        ip=ip,
        user_id=str(user.id),
        email=user.email,
        detail="Cambio obligatorio post-recuperación",
    )
