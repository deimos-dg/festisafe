from pydantic import BaseModel, EmailStr, Field
from datetime import datetime
from uuid import UUID
from typing import Optional


class UserResponse(BaseModel):
    """Perfil completo — solo para /users/me y endpoints admin."""
    id: UUID
    name: str
    email: EmailStr
    phone: Optional[str] = None
    role: str
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True


class UserPublicResponse(BaseModel):
    """Perfil público — expuesto en /users/{user_id}. Sin datos sensibles."""
    id: UUID
    name: str
    role: str

    class Config:
        from_attributes = True


class UserUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=2, max_length=100)
    phone: Optional[str] = Field(None, max_length=30)


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(..., min_length=12)


class FcmTokenRequest(BaseModel):
    token: str = Field(..., min_length=10, max_length=512)
    platform: str = Field(default="android", pattern="^(android|ios)$")
