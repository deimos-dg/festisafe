"""
Unit tests para PasswordRecoveryService.

Cubre:
- Property 5: SMTP error → HTTP 503
- Property 8 (reset flow): reset exitoso establece must_change_password=False y password_changed_at actualizado
- Requirement 4.5: change-password sin JWT devuelve 401
- Property 18: completitud del audit log (campos ip, email/user_id, result)

Requirements: 2.3, 3.2, 4.5, 8.1, 8.2
"""
import hashlib
import os
import secrets
import sys
import uuid
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch, call

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Proveer variables de entorno requeridas antes de importar settings
os.environ.setdefault("SECRET_KEY", "test-secret-key-at-least-32-characters-long")
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

# ---------------------------------------------------------------------------
# Patch create_engine para que ignore args incompatibles con SQLite.
# app.db.session se importa a nivel de módulo con pool args de PostgreSQL;
# cuando DATABASE_URL es sqlite:///:memory: esos args causan TypeError.
# ---------------------------------------------------------------------------
_original_create_engine = create_engine

def _sqlite_safe_create_engine(url, **kwargs):
    url_str = str(url)
    if url_str.startswith("sqlite"):
        kwargs.pop("max_overflow", None)
        kwargs.pop("pool_timeout", None)
        kwargs.pop("pool_size", None)
        kwargs.pop("pool_recycle", None)
        kwargs.pop("pool_pre_ping", None)
    return _original_create_engine(url, **kwargs)

# Aplicar el patch antes de que app.db.session sea importado
import sqlalchemy
sqlalchemy.create_engine = _sqlite_safe_create_engine

# Ahora es seguro importar módulos de la app que usan create_engine
from app.db.base import Base
from app.db.models.user import User
from app.db.models.password_reset_token import PasswordResetToken
from app.core.security import hash_password
from app.crud.password_reset_token import create_reset_token
from app.services.password_recovery import (
    request_password_recovery,
    reset_password,
)
from app.core.email_service import EmailDeliveryError
from fastapi.testclient import TestClient


# ---------------------------------------------------------------------------
# Helpers de BD en memoria (mismo patrón que test_password_recovery_service_properties.py)
# ---------------------------------------------------------------------------

def _make_db():
    """Crea una sesión SQLite en memoria con todas las tablas."""
    engine = _sqlite_safe_create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    return Session(), engine


def _make_user(db, email="user@example.com", password="hashed_pw", must_change=False, is_active=True):
    user = User(
        id=uuid.uuid4(),
        email=email,
        hashed_password=password,
        name="Test User",
        is_active=is_active,
        must_change_password=must_change,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


# ---------------------------------------------------------------------------
# Helpers para TestClient con BD en memoria
# ---------------------------------------------------------------------------

def _make_test_app(db_session):
    """
    Crea una app FastAPI mínima con el router de auth, usando la sesión
    SQLite en memoria proporcionada.
    """
    import importlib
    from fastapi import FastAPI
    from fastapi.responses import JSONResponse
    from slowapi.errors import RateLimitExceeded
    from app.core.limiter import limiter
    from app.core.database import get_db as core_get_db
    from app.db.session import get_db as session_get_db

    # Importar el router de auth directamente (evita el __init__ del paquete)
    auth_mod = importlib.import_module("app.api.v1.endpoints.auth")
    auth_router = auth_mod.router

    test_app = FastAPI()
    test_app.state.limiter = limiter
    test_app.include_router(auth_router, prefix="/api/v1")

    @test_app.exception_handler(RateLimitExceeded)
    async def rate_limit_handler(request, exc):
        return JSONResponse(status_code=429, content={"detail": "Too many requests"})

    def override_get_db():
        try:
            yield db_session
        finally:
            pass

    # Sobrescribir ambas referencias a get_db para garantizar que el override aplique
    test_app.dependency_overrides[core_get_db] = override_get_db
    test_app.dependency_overrides[session_get_db] = override_get_db
    return test_app


def _make_db_on_session_engine():
    """
    Crea tablas en el engine de app.db.session y devuelve una sesión sobre él.
    Usa StaticPool para que todas las conexiones (incluyendo las del TestClient
    en otro hilo) compartan la misma BD SQLite en memoria.
    """
    from sqlalchemy.pool import StaticPool
    from app.db.session import SessionLocal
    # Crear un engine con StaticPool para compartir la conexión entre hilos
    shared_engine = _sqlite_safe_create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(shared_engine)
    SharedSession = sessionmaker(bind=shared_engine)
    return SharedSession(), shared_engine


# ---------------------------------------------------------------------------
# Test 1: SMTP error → HTTP 503
# Feature: password-recovery, Property 5
# Validates: Requirements 2.3
# ---------------------------------------------------------------------------

def test_smtp_error_returns_503():
    """
    Cuando send_recovery_email lanza EmailDeliveryError, el endpoint
    /auth/forgot-password debe responder con HTTP 503 y el mensaje esperado.

    # Feature: password-recovery, Property 5
    Validates: Requirements 2.3
    """
    db, engine = _make_db_on_session_engine()
    try:
        _make_user(db, email="smtp-fail@example.com", is_active=True)

        test_app = _make_test_app(db)

        with patch(
            "app.services.password_recovery.send_recovery_email",
            side_effect=EmailDeliveryError("SMTP connection refused"),
        ):
            client = TestClient(test_app, raise_server_exceptions=False)
            response = client.post(
                "/api/v1/auth/forgot-password",
                json={"email": "smtp-fail@example.com"},
            )

        assert response.status_code == 503, (
            f"Se esperaba 503, se obtuvo {response.status_code}: {response.text}"
        )
        body = response.json()
        assert body["detail"] == "No se pudo enviar el email de recuperación. Inténtalo más tarde.", (
            f"Mensaje inesperado: {body['detail']!r}"
        )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


# ---------------------------------------------------------------------------
# Test 2: Reset exitoso establece must_change_password=False y password_changed_at actualizado
# Feature: password-recovery, Property 8 (reset flow)
# Validates: Requirements 3.2
# ---------------------------------------------------------------------------

def test_successful_reset_clears_must_change_password_and_updates_changed_at():
    """
    Después de reset_password exitoso con un token válido:
    - user.must_change_password debe ser False
    - user.password_changed_at debe ser no nulo y >= before

    # Feature: password-recovery, Property 8 (reset flow)
    Validates: Requirements 3.2
    """
    db, engine = _make_db()
    try:
        user = _make_user(
            db,
            email="reset-success@example.com",
            password=hash_password("OldPass1!XYZabc"),
            must_change=True,
        )

        # Crear token válido en BD
        token_plain = secrets.token_hex(32)
        token_hash = hashlib.sha256(token_plain.encode()).hexdigest()
        expires_at = datetime.utcnow() + timedelta(minutes=30)
        create_reset_token(db, user.id, token_hash, expires_at)

        before = datetime.utcnow()

        reset_password(
            db=db,
            token=token_plain,
            new_password="NewValidPass1!XYZ",
            ip="127.0.0.1",
        )

        db.refresh(user)

        assert user.must_change_password is False, (
            "must_change_password debe ser False después del reset exitoso"
        )
        assert user.password_changed_at is not None, (
            "password_changed_at no debe ser None después del reset"
        )
        assert user.password_changed_at >= before, (
            "password_changed_at debe ser posterior al inicio de la operación"
        )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


# ---------------------------------------------------------------------------
# Test 3: change-password sin JWT devuelve 401
# Feature: password-recovery, Requirement 4.5
# Validates: Requirements 4.5
# ---------------------------------------------------------------------------

def test_change_password_without_jwt_returns_401():
    """
    Una llamada a POST /auth/change-password sin cabecera Authorization
    debe devolver HTTP 401.

    # Feature: password-recovery, Requirement 4.5
    Validates: Requirements 4.5
    """
    db, engine = _make_db_on_session_engine()
    try:
        test_app = _make_test_app(db)
        client = TestClient(test_app, raise_server_exceptions=False)
        response = client.post(
            "/api/v1/auth/change-password",
            json={
                "current_password": "OldPass1!XYZabc",
                "new_password": "NewPass2!XYZabc",
                "confirm_password": "NewPass2!XYZabc",
            },
            # Sin cabecera Authorization
        )

        assert response.status_code == 401, (
            f"Se esperaba 401, se obtuvo {response.status_code}: {response.text}"
        )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


# ---------------------------------------------------------------------------
# Test 4: Completitud del audit log
# Feature: password-recovery, Property 18
# Validates: Requirements 8.1, 8.2
# ---------------------------------------------------------------------------

def test_audit_log_completeness_request_and_reset():
    """
    Verifica que log_security_event es llamado con los campos requeridos
    (ip, email/user_id, event) durante request_password_recovery y reset_password.

    - request_password_recovery debe registrar PASSWORD_RESET_REQUESTED con ip y email.
    - reset_password exitoso debe registrar PASSWORD_CHANGED con ip, user_id y email.

    # Feature: password-recovery, Property 18
    Validates: Requirements 8.1, 8.2
    """
    from app.core.audit_log import AuditEvent

    db, engine = _make_db()
    try:
        user = _make_user(
            db,
            email="audit@example.com",
            password=hash_password("OldPass1!XYZabc"),
            must_change=False,
        )

        # --- request_password_recovery ---
        with patch("app.services.password_recovery.send_recovery_email"):
            with patch("app.services.password_recovery.log_security_event") as mock_log:
                request_password_recovery(db, email="audit@example.com", ip="10.0.0.1")

        # Debe haber al menos una llamada con PASSWORD_RESET_REQUESTED
        events_logged = [c.args[0] if c.args else c.kwargs.get("event") for c in mock_log.call_args_list]
        assert AuditEvent.PASSWORD_RESET_REQUESTED in events_logged, (
            f"Se esperaba PASSWORD_RESET_REQUESTED en el audit log, se obtuvo: {events_logged}"
        )

        # Verificar que la llamada incluye ip y email
        reset_requested_call = next(
            c for c in mock_log.call_args_list
            if (c.args and c.args[0] == AuditEvent.PASSWORD_RESET_REQUESTED)
            or c.kwargs.get("event") == AuditEvent.PASSWORD_RESET_REQUESTED
        )
        kwargs = reset_requested_call.kwargs
        assert kwargs.get("ip") == "10.0.0.1", (
            f"ip esperada '10.0.0.1', se obtuvo {kwargs.get('ip')!r}"
        )
        assert kwargs.get("email") == "audit@example.com", (
            f"email esperado 'audit@example.com', se obtuvo {kwargs.get('email')!r}"
        )

        # --- reset_password ---
        token_plain = secrets.token_hex(32)
        token_hash = hashlib.sha256(token_plain.encode()).hexdigest()
        expires_at = datetime.utcnow() + timedelta(minutes=30)
        create_reset_token(db, user.id, token_hash, expires_at)

        with patch("app.services.password_recovery.log_security_event") as mock_log_reset:
            reset_password(
                db=db,
                token=token_plain,
                new_password="NewValidPass1!XYZ",
                ip="10.0.0.2",
            )

        events_reset = [c.args[0] if c.args else c.kwargs.get("event") for c in mock_log_reset.call_args_list]
        assert AuditEvent.PASSWORD_CHANGED in events_reset, (
            f"Se esperaba PASSWORD_CHANGED en el audit log, se obtuvo: {events_reset}"
        )

        # Verificar que la llamada PASSWORD_CHANGED incluye ip, user_id y email
        changed_call = next(
            c for c in mock_log_reset.call_args_list
            if (c.args and c.args[0] == AuditEvent.PASSWORD_CHANGED)
            or c.kwargs.get("event") == AuditEvent.PASSWORD_CHANGED
        )
        kwargs_changed = changed_call.kwargs
        assert kwargs_changed.get("ip") == "10.0.0.2", (
            f"ip esperada '10.0.0.2', se obtuvo {kwargs_changed.get('ip')!r}"
        )
        assert kwargs_changed.get("user_id") == str(user.id), (
            f"user_id esperado {str(user.id)!r}, se obtuvo {kwargs_changed.get('user_id')!r}"
        )
        assert kwargs_changed.get("email") == "audit@example.com", (
            f"email esperado 'audit@example.com', se obtuvo {kwargs_changed.get('email')!r}"
        )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()
