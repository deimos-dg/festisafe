from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from typing import List, Generator
from datetime import datetime

from app.db.session import get_db
from app.core.security import decode_token
from app.core.config import settings
from app.crud.revoked_token import is_token_revoked
from app.db.models.user import User
from app.db.models.company import Company, CompanyStatus

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token inválido o expirado",
        headers={"WWW-Authenticate": "Bearer"},
    )

    payload = decode_token(token)

    user_id = payload.get("sub")
    token_type = payload.get("type")
    issued_at = payload.get("iat")

    if not user_id or not token_type or not issued_at:
        raise credentials_exception

    if token_type != "access":
        raise credentials_exception

    jti = payload.get("jti")
    if jti and is_token_revoked(db, jti):
        raise credentials_exception

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise credentials_exception

    if user.is_locked:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cuenta bloqueada temporalmente",
        )

    if user.must_change_password:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Debes cambiar tu contraseña",
        )

    if user.password_changed_at:
        token_issued_at = datetime.fromtimestamp(issued_at)
        if token_issued_at < user.password_changed_at:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Sesión expirada por cambio de contraseña",
            )

    # Verificar que la empresa del usuario no esté suspendida
    if user.company_id:
        company = db.query(Company).filter(Company.id == user.company_id).first()
        if company and company.status == CompanyStatus.suspended:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Tu empresa está suspendida. Contacta al administrador.",
            )

    return user


def get_current_active_user(
    current_user: User = Depends(get_current_user),
):
    if not current_user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Usuario inactivo",
        )
    return current_user


def get_current_user_allow_password_change(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    """
    Igual que get_current_user pero NO bloquea si must_change_password=True.
    Usado exclusivamente en el endpoint change-password.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token inválido o expirado",
        headers={"WWW-Authenticate": "Bearer"},
    )

    payload = decode_token(token)
    user_id = payload.get("sub")
    token_type = payload.get("type")

    if not user_id or token_type != "access":
        raise credentials_exception

    jti = payload.get("jti")
    if jti and is_token_revoked(db, jti):
        raise credentials_exception

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise credentials_exception

    if user.is_locked:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cuenta bloqueada temporalmente")

    # Verificar que el token no fue emitido antes del último cambio de contraseña
    issued_at = payload.get("iat")
    if issued_at and user.password_changed_at:
        token_issued_at = datetime.fromtimestamp(issued_at)
        if token_issued_at < user.password_changed_at:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Sesión expirada por cambio de contraseña",
            )

    return user


def require_roles(allowed_roles: List[str]):
    def role_checker(current_user: User = Depends(get_current_user)):
        if current_user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tienes permisos para acceder a este recurso",
            )
        return current_user
    return role_checker
