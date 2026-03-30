from pydantic import BaseModel, EmailStr, Field, field_validator
from app.schemas.user import UserResponse
from app.core.validators import validate_password, validate_phone


class AuthResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str
    user: UserResponse


class TokenRefreshRequest(BaseModel):
    refresh_token: str


class UserCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=100)
    email: EmailStr
    password: str = Field(..., min_length=12)
    confirm_password: str = Field(..., min_length=12)
    phone: str | None = None
    is_organizer: bool = False

    @field_validator("name", "password", mode="before")
    @classmethod
    def not_empty(cls, value):
        if isinstance(value, str) and not value.strip():
            raise ValueError("El campo no puede estar vacío")
        return value

    @field_validator("password")
    @classmethod
    def strong_password(cls, value):
        validate_password(value)
        return value

    @field_validator("confirm_password")
    @classmethod
    def passwords_match(cls, value, info):
        if info.data.get("password") and value != info.data["password"]:
            raise ValueError("Las contraseñas no coinciden")
        return value

    @field_validator("phone")
    @classmethod
    def valid_phone(cls, value):
        if value is not None and value.strip():
            return validate_phone(value)
        return value


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class GuestLoginRequest(BaseModel):
    """Canjea un código de 6 dígitos para acceder como invitado."""
    code: str = Field(..., min_length=6, max_length=6, pattern=r"^\d{6}$")


class GuestCodeResponse(BaseModel):
    """Respuesta al generar un código de invitado."""
    code: str
    expires_at: str
    remaining_uses: int
    event_id: str

    class Config:
        from_attributes = True


class ConvertGuestRequest(BaseModel):
    """Convierte una cuenta de invitado en cuenta permanente."""
    email: EmailStr
    password: str = Field(..., min_length=12)
    phone: str | None = None

    @field_validator("password")
    @classmethod
    def strong_password(cls, value):
        validate_password(value)
        return value


class ForgotPasswordRequest(BaseModel):
    """Solicitud de recuperación de contraseña."""
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    """Restablece la contraseña usando un token de recuperación."""
    token: str = Field(..., min_length=64, max_length=64)
    new_password: str = Field(..., min_length=12)
    confirm_password: str = Field(..., min_length=12)

    @field_validator("new_password")
    @classmethod
    def strong_password(cls, value):
        validate_password(value)
        return value

    @field_validator("confirm_password")
    @classmethod
    def passwords_match(cls, value, info):
        if info.data.get("new_password") and value != info.data["new_password"]:
            raise ValueError("Las contraseñas no coinciden")
        return value


class ChangePasswordRequest(BaseModel):
    """Cambia la contraseña de un usuario autenticado con must_change_password=True."""
    current_password: str
    new_password: str = Field(..., min_length=12)
    confirm_password: str = Field(..., min_length=12)

    @field_validator("new_password")
    @classmethod
    def strong_password(cls, value):
        validate_password(value)
        return value

    @field_validator("confirm_password")
    @classmethod
    def passwords_match(cls, value, info):
        if info.data.get("new_password") and value != info.data["new_password"]:
            raise ValueError("Las contraseñas no coinciden")
        return value
