"""
Funciones de seguridad: hashing, JWT, brute-force protection.
"""
import uuid
import hashlib
import hmac
import bcrypt
from datetime import datetime, timedelta

from jose import jwt, JWTError
from fastapi import HTTPException, status

from app.core.config import settings


# =========================
# PASSWORDS
# =========================

def _prepare_password(password: str) -> bytes:
    """
    Pre-hashea con SHA-256 antes de bcrypt para:
    1. Evitar el límite de 72 bytes de bcrypt con contraseñas largas.
    2. Normalizar el input antes del hash costoso.
    """
    return hashlib.sha256(password.encode("utf-8")).hexdigest().encode("utf-8")


def hash_password(password: str) -> str:
    pwd_bytes = _prepare_password(password)
    return bcrypt.hashpw(pwd_bytes, bcrypt.gensalt(rounds=12)).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verificación en tiempo constante para prevenir timing attacks.
    bcrypt.checkpw ya es tiempo-constante internamente, pero usamos
    hmac.compare_digest en la capa de string para doble protección.
    """
    pwd_bytes = _prepare_password(plain_password)
    try:
        result = bcrypt.checkpw(pwd_bytes, hashed_password.encode("utf-8"))
    except Exception:
        return False
    # compare_digest evita short-circuit en la comparación booleana
    return hmac.compare_digest(str(result), str(True))


# =========================
# JWT
# =========================

def create_access_token(user_id: str, email: str) -> str:
    return _create_token(
        data={"sub": str(user_id), "email": email},
        expires_delta=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
        token_type="access",
    )


def create_refresh_token(user_id: str, email: str) -> str:
    return _create_token(
        data={"sub": str(user_id), "email": email},
        expires_delta=timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        token_type="refresh",
    )


def _create_token(data: dict, expires_delta: timedelta, token_type: str) -> str:
    to_encode = data.copy()
    now = datetime.utcnow()
    expire = now + expires_delta

    to_encode.update({
        "exp": expire,
        "iat": now,
        "nbf": now,                  # not-before: el token no es válido antes de ahora
        "type": token_type,
        "jti": str(uuid.uuid4()),    # ID único para revocación individual
    })

    return jwt.encode(
        to_encode,
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM,
    )


def decode_token(token: str) -> dict:
    """
    Decodifica y valida un JWT.
    Verifica firma, expiración y nbf automáticamente.
    """
    try:
        payload = jwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
            options={"verify_exp": True, "verify_nbf": True},
        )
        return payload
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token inválido o expirado",
            headers={"WWW-Authenticate": "Bearer"},
        )


# =========================
# BRUTE FORCE PROTECTION
# =========================

# Umbrales de bloqueo progresivo
_LOCK_THRESHOLDS = [
    (3, timedelta(minutes=3)),    # 3 intentos → 3 min
    (5, timedelta(minutes=15)),   # 5 intentos → 15 min
    (8, timedelta(hours=1)),      # 8 intentos → 1 hora
    (10, timedelta(hours=24)),    # 10+ intentos → 24 horas
]


def register_failed_attempt(user, db) -> None:
    """
    Bloqueo progresivo por intentos fallidos.
    A los 6+ intentos activa must_change_password.
    """
    user.failed_login_attempts += 1
    attempts = user.failed_login_attempts

    # Determinar duración de bloqueo según umbral
    lock_duration = None
    for threshold, duration in _LOCK_THRESHOLDS:
        if attempts >= threshold:
            lock_duration = duration

    if lock_duration is not None:
        user.lock_until = datetime.utcnow() + lock_duration
        user.is_locked = True

    if attempts >= 6:
        user.must_change_password = True

    db.commit()


def reset_login_attempts(user, db) -> None:
    """Limpia el estado de bloqueo tras login exitoso."""
    user.failed_login_attempts = 0
    user.lock_until = None
    user.is_locked = False
    db.commit()
