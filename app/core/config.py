"""
Configuración centralizada de la aplicación.
Todas las variables sensibles se leen desde variables de entorno / Secrets Manager.
"""
from pydantic_settings import BaseSettings
from typing import List
from pydantic import AnyHttpUrl, field_validator


class Settings(BaseSettings):
    # Proyecto
    PROJECT_NAME: str = "FestiSafe"
    VERSION: str = "2.1.0"
    API_V1_STR: str = "/api/v1"

    # Modo
    DEBUG: bool = False

    # Seguridad / JWT
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # Base de datos
    DATABASE_URL: str

    @field_validator("DATABASE_URL", mode="before")
    @classmethod
    def fix_postgres_protocol(cls, v: str) -> str:
        if v and v.startswith("postgres://"):
            return v.replace("postgres://", "postgresql+psycopg2://", 1)
        if v and v.startswith("postgresql://"):
             return v.replace("postgresql://", "postgresql+psycopg2://", 1)
        return v

    # CORS — lista explícita de orígenes permitidos
    # En producción debe ser la URL del frontend/app, nunca "*"
    BACKEND_CORS_ORIGINS: List[str] = ["*"]

    # Hosts permitidos — previene Host header injection y enmascaramiento de puertos
    # En producción: ["festisafe-alb-814303465.us-east-1.elb.amazonaws.com", "api.festisafe.com"]
    # En desarrollo: ["*"] (acepta cualquier host)
    ALLOWED_HOSTS: List[str] = ["*"]

    # Tamaño máximo del body de requests (bytes) — 1 MB por defecto
    MAX_REQUEST_BODY_SIZE: int = 1_048_576  # 1 MB

    # Docs — deshabilitar en producción
    ENABLE_DOCS: bool = False

    # Firebase Admin SDK — para notificaciones push FCM
    # Opción 1: JSON completo del service account como string
    FIREBASE_SERVICE_ACCOUNT_JSON: str = ""
    # Opción 2: Ruta al archivo JSON del service account
    FIREBASE_SERVICE_ACCOUNT_PATH: str = ""

    # SMTP — para emails transaccionales (recuperación de contraseña)
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_FROM: str = ""

    # Deep link base para emails (ej: "festisafe://")
    APP_DEEP_LINK_BASE: str = ""

    # Logging de seguridad
    SECURITY_LOG_LEVEL: str = "INFO"

    # Stripe — pagos B2B
    STRIPE_SECRET_KEY: str = ""
    STRIPE_WEBHOOK_SECRET: str = ""

    @field_validator("SECRET_KEY")
    @classmethod
    def secret_key_strength(cls, v: str) -> str:
        if len(v) < 32:
            raise ValueError("SECRET_KEY debe tener al menos 32 caracteres")
        return v

    @field_validator("ALGORITHM")
    @classmethod
    def algorithm_allowed(cls, v: str) -> str:
        allowed = {"HS256", "HS384", "HS512"}
        if v not in allowed:
            raise ValueError(f"ALGORITHM debe ser uno de: {allowed}")
        return v

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
