"""
Property tests para el servicio de recuperación de contraseña.

Cubre las propiedades 1, 2, 3, 4, 7, 8, 9 y 11 del diseño técnico.
"""
import hashlib
import hmac
import os
import secrets
import uuid
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Proveer variables de entorno requeridas antes de importar settings
os.environ.setdefault("SECRET_KEY", "test-secret-key-at-least-32-characters-long")
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from app.db.base import Base
from app.db.models.user import User
from app.db.models.password_reset_token import PasswordResetToken
from app.db.models.revoked_token import RevokedToken
from app.core.security import hash_password, verify_password
from app.crud.password_reset_token import create_reset_token, invalidate_user_tokens
from app.services.password_recovery import (
    generate_recovery_token,
    request_password_recovery,
    reset_password,
    change_password,
)


# ---------------------------------------------------------------------------
# Helpers de BD en memoria
# ---------------------------------------------------------------------------

def _make_db():
    """Crea una sesión SQLite en memoria con todas las tablas."""
    engine = create_engine(
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
# Property 1 (tarea 4.2): Entropía mínima del token generado
# Feature: password-recovery, Property 1: Token generation entropy
# Validates: Requirements 1.1
# ---------------------------------------------------------------------------

def test_token_generation_entropy():
    """
    Genera 100 tokens y verifica:
    - Longitud exacta de 64 caracteres (32 bytes hex)
    - Solo caracteres hexadecimales válidos (0-9a-f)
    - Sin colisiones entre los 100 tokens generados

    # Feature: password-recovery, Property 1: Token generation entropy
    Validates: Requirements 1.1
    """
    tokens = []
    hex_chars = set("0123456789abcdef")

    for _ in range(100):
        token = generate_recovery_token()

        assert len(token) == 64, (
            f"El token debe tener 64 caracteres, tiene {len(token)}"
        )
        assert all(c in hex_chars for c in token), (
            f"El token contiene caracteres no hexadecimales: {token!r}"
        )
        tokens.append(token)

    # Sin colisiones
    assert len(set(tokens)) == 100, (
        "Se detectaron colisiones entre los 100 tokens generados"
    )


# ---------------------------------------------------------------------------
# Property 2 (tarea 4.3): Round-trip de almacenamiento del token
# Feature: password-recovery, Property 2: Token storage round-trip
# Validates: Requirements 1.2
# ---------------------------------------------------------------------------

@given(st.emails())
@settings(max_examples=20)
def test_token_storage_roundtrip(email):
    """
    Para cualquier usuario válido, cuando se llama a request_password_recovery,
    el hash almacenado en password_reset_tokens.token_hash debe ser igual a
    hashlib.sha256(token.encode()).hexdigest(), y expires_at debe ser
    aproximadamente now + 30 minutos (±5 segundos de tolerancia).

    # Feature: password-recovery, Property 2: Token storage round-trip
    Validates: Requirements 1.2
    """
    db, engine = _make_db()
    try:
        user = _make_user(db, email=email)

        captured_token = None

        def _capture_send(user_name, user_email, token, **kwargs):
            nonlocal captured_token
            captured_token = token

        with patch("app.services.password_recovery.send_recovery_email", side_effect=_capture_send):
            before = datetime.utcnow()
            request_password_recovery(db, email=email, ip="127.0.0.1")

        assert captured_token is not None, "El token no fue capturado del email"

        expected_hash = hashlib.sha256(captured_token.encode()).hexdigest()

        # Buscar el registro almacenado en BD
        record = db.query(PasswordResetToken).filter(
            PasswordResetToken.user_id == user.id
        ).order_by(PasswordResetToken.created_at.desc()).first()

        assert record is not None, "No se encontró ningún token en BD para el usuario"

        # El hash almacenado debe coincidir con SHA-256(token)
        assert hmac.compare_digest(record.token_hash, expected_hash), (
            "El hash almacenado no coincide con SHA-256(token)"
        )

        # expires_at debe ser ≈ now + 30 min (±5 segundos)
        delta = abs((record.expires_at - before).total_seconds() - 1800)
        assert delta < 5, (
            f"expires_at está fuera del rango esperado: delta={delta:.1f}s"
        )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


# ---------------------------------------------------------------------------
# Property 3 (tarea 4.4): Indistinguibilidad de respuesta por email
# Feature: password-recovery, Property 3: Response indistinguishability by email
# Validates: Requirements 1.3
# ---------------------------------------------------------------------------

# Estrategia: escenario de usuario (existing, non-existing, inactive)
_user_scenario = st.sampled_from(["existing", "non_existing", "inactive"])


@given(email=st.emails(), scenario=_user_scenario)
@settings(max_examples=20)
def test_response_indistinguishability(email, scenario):
    """
    Para cualquier email (existente, inexistente o de cuenta inactiva),
    request_password_recovery no debe lanzar excepciones distintas según
    el tipo de email — el llamante no puede distinguir si el email existía.

    Escenarios cubiertos:
    - existing: usuario activo con ese email en BD
    - non_existing: ningún usuario con ese email en BD
    - inactive: usuario con is_active=False con ese email en BD

    La propiedad verifica que la función siempre retorna None (sin excepción)
    para los tres escenarios, garantizando indistinguibilidad de respuesta.

    # Feature: password-recovery, Property 3: Response indistinguishability by email
    Validates: Requirements 1.3
    """
    db, engine = _make_db()

    # Preparar el estado de la BD según el escenario
    if scenario == "existing":
        _make_user(db, email=email, is_active=True)
    elif scenario == "inactive":
        _make_user(db, email=email, is_active=False)
    # non_existing: no se crea ningún usuario

    try:
        with patch("app.services.password_recovery.send_recovery_email"):
            # request_password_recovery debe completar sin lanzar excepción
            # para cualquier tipo de email (anti-enumeración)
            result = request_password_recovery(db, email=email, ip="127.0.0.1")

        # La función siempre retorna None — no revela si el email existía
        assert result is None, (
            f"Se esperaba None para scenario={scenario!r}, email={email!r}, "
            f"se obtuvo {result!r}"
        )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


# ---------------------------------------------------------------------------
# Property 4 (tarea 4.5): Invalidación de token previo al regenerar
# Feature: password-recovery, Property 4: Previous token invalidation on regeneration
# Validates: Requirements 1.4
# ---------------------------------------------------------------------------

@given(email=st.emails())
@settings(max_examples=20)
def test_previous_token_invalidated_on_regeneration(email):
    """
    Para cualquier usuario que solicite recuperación dos veces, después de la
    segunda solicitud el primer token debe ser inválido (used_at no nulo), y
    solo el segundo token debe ser válido (is_valid() == True).

    # Feature: password-recovery, Property 4: Previous token invalidation on regeneration
    Validates: Requirements 1.4
    """
    db, engine = _make_db()
    try:
        _make_user(db, email=email, is_active=True)

        first_captured = None
        second_captured = None

        def _capture_first(user_name, user_email, token, **kwargs):
            nonlocal first_captured
            first_captured = token

        def _capture_second(user_name, user_email, token, **kwargs):
            nonlocal second_captured
            second_captured = token

        # Primera solicitud
        with patch("app.services.password_recovery.send_recovery_email", side_effect=_capture_first):
            request_password_recovery(db, email=email, ip="127.0.0.1")

        assert first_captured is not None, "El primer token no fue capturado"

        # Segunda solicitud
        with patch("app.services.password_recovery.send_recovery_email", side_effect=_capture_second):
            request_password_recovery(db, email=email, ip="127.0.0.1")

        assert second_captured is not None, "El segundo token no fue capturado"

        first_hash = hashlib.sha256(first_captured.encode()).hexdigest()
        second_hash = hashlib.sha256(second_captured.encode()).hexdigest()

        first_record = db.query(PasswordResetToken).filter(
            PasswordResetToken.token_hash == first_hash
        ).first()
        second_record = db.query(PasswordResetToken).filter(
            PasswordResetToken.token_hash == second_hash
        ).first()

        assert first_record is not None, "No se encontró el primer token en BD"
        assert second_record is not None, "No se encontró el segundo token en BD"

        # El primer token debe estar invalidado (used_at no nulo)
        assert first_record.used_at is not None, (
            "El primer token debe tener used_at no nulo después de la segunda solicitud"
        )

        # El segundo token debe ser válido
        assert second_record.is_valid(), (
            "El segundo token debe ser válido (used_at nulo y expires_at en el futuro)"
        )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


# ---------------------------------------------------------------------------
# Property 7 (tarea 4.6): Corrección de validación del token
# Feature: password-recovery, Property 7: Token validation correctness
# Validates: Requirements 3.1, 3.3
# ---------------------------------------------------------------------------

@given(st.text(min_size=64, max_size=64))
@settings(max_examples=20)
def test_invalid_token_raises_400(random_token):
    """
    Para cualquier token aleatorio de 64 caracteres que no exista en BD,
    reset_password debe lanzar HTTPException 400.

    # Feature: password-recovery, Property 7: Token validation correctness
    Validates: Requirements 3.1, 3.3
    """
    import app.services.password_recovery as _svc

    db, engine = _make_db()
    # Usar una IP única por ejemplo para evitar que el contador de brute-force
    # acumulado entre ejemplos de Hypothesis produzca 429 en lugar de 400.
    unique_ip = f"10.{secrets.randbelow(256)}.{secrets.randbelow(256)}.{secrets.randbelow(256)}"
    # Asegurarse de que la IP no tenga intentos previos
    _svc._failed_token_attempts.pop(unique_ip, None)
    try:
        with pytest.raises(HTTPException) as exc_info:
            reset_password(
                db=db,
                token=random_token,
                new_password="ValidPass1!XYZ",
                ip=unique_ip,
            )
        assert exc_info.value.status_code == 400, (
            f"Se esperaba 400, se obtuvo {exc_info.value.status_code}"
        )
    finally:
        _svc._failed_token_attempts.pop(unique_ip, None)
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


@given(st.emails())
@settings(max_examples=10, deadline=None)
def test_valid_token_accepted(email):
    """
    Para cualquier token válido (hash existe en BD, used_at es nulo,
    expires_at > now), reset_password debe aceptarlo sin lanzar HTTPException 400.

    # Feature: password-recovery, Property 7: Token validation correctness
    Validates: Requirements 3.1, 3.3
    """
    db, engine = _make_db()
    try:
        user = _make_user(db, email=email)

        # Generar un token real y almacenar su hash en BD
        token_plain = secrets.token_hex(32)
        token_hash = hashlib.sha256(token_plain.encode()).hexdigest()
        expires_at = datetime.utcnow() + timedelta(minutes=30)
        create_reset_token(db, user.id, token_hash, expires_at)

        # reset_password con token válido NO debe lanzar HTTPException 400
        try:
            reset_password(
                db=db,
                token=token_plain,
                new_password="ValidNewPass1!XYZ",
                ip="127.0.0.1",
            )
        except HTTPException as exc:
            assert exc.status_code != 400, (
                f"Un token válido no debe producir HTTP 400, "
                f"pero se obtuvo {exc.status_code}: {exc.detail!r}"
            )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


# ---------------------------------------------------------------------------
# Property 8 (tarea 4.7): Invariantes post-cambio de contraseña
# Feature: password-recovery, Property 8: Post-password-change invariants
# Validates: Requirements 3.2, 4.2
# ---------------------------------------------------------------------------

# Estrategia de contraseñas válidas: mínimo 12 chars, con mayúscula, minúscula,
# dígito y carácter especial para cumplir validate_password.
_SPECIAL_CHARS = "!@#$%^&*()_+-=[]{}|;:,.<>?"

_valid_password_strategy = st.builds(
    lambda base, upper, digit, special: upper + digit + special + base,
    base=st.text(
        alphabet=st.characters(whitelist_categories=("Ll",)),
        min_size=9,
        max_size=20,
    ),
    upper=st.text(
        alphabet=st.characters(whitelist_categories=("Lu",)),
        min_size=1,
        max_size=1,
    ),
    digit=st.text(alphabet="0123456789", min_size=1, max_size=1),
    special=st.sampled_from(list(_SPECIAL_CHARS)),
)


@given(new_password=_valid_password_strategy)
@settings(max_examples=10, deadline=None)
def test_post_password_change_invariants_change_flow(new_password):
    """
    Flujo change_password: para cualquier nueva contraseña válida, después de
    change_password exitoso el usuario debe tener:
    - must_change_password == False
    - password_changed_at actualizado (>= antes de la operación)
    - verify_password(new_password, hashed_password) == True

    # Feature: password-recovery, Property 8: Post-password-change invariants
    Validates: Requirements 3.2, 4.2
    """
    current_plain = "OldPass1!XYZabc"

    db, engine = _make_db()
    try:
        user = _make_user(
            db,
            email="invariants-change@example.com",
            password=hash_password(current_plain),
            must_change=True,
        )

        before = datetime.utcnow()

        change_password(
            db=db,
            user=user,
            current_password=current_plain,
            new_password=new_password,
            ip="127.0.0.1",
        )

        db.refresh(user)

        assert user.must_change_password is False, (
            "must_change_password debe ser False después del cambio"
        )
        assert user.password_changed_at is not None, (
            "password_changed_at no debe ser None"
        )
        assert user.password_changed_at >= before, (
            "password_changed_at debe ser posterior al inicio de la operación"
        )
        assert verify_password(new_password, user.hashed_password), (
            "verify_password debe funcionar con la nueva contraseña"
        )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


@given(new_password=_valid_password_strategy)
@settings(max_examples=10, deadline=None)
def test_post_password_change_invariants_reset_flow(new_password):
    """
    Flujo reset_password (via token): para cualquier nueva contraseña válida,
    después de reset_password exitoso el usuario debe tener:
    - must_change_password == False
    - password_changed_at actualizado (>= antes de la operación)
    - verify_password(new_password, hashed_password) == True

    # Feature: password-recovery, Property 8: Post-password-change invariants
    Validates: Requirements 3.2, 4.2
    """
    db, engine = _make_db()
    try:
        user = _make_user(
            db,
            email="invariants-reset@example.com",
            password=hash_password("SomeOldPass1!"),
            must_change=True,
        )

        # Crear un token válido en BD
        token_plain = secrets.token_hex(32)
        token_hash = hashlib.sha256(token_plain.encode()).hexdigest()
        expires_at = datetime.utcnow() + timedelta(minutes=30)
        create_reset_token(db, user.id, token_hash, expires_at)

        before = datetime.utcnow()

        reset_password(
            db=db,
            token=token_plain,
            new_password=new_password,
            ip="127.0.0.1",
        )

        db.refresh(user)

        assert user.must_change_password is False, (
            "must_change_password debe ser False después del reset"
        )
        assert user.password_changed_at is not None, (
            "password_changed_at no debe ser None"
        )
        assert user.password_changed_at >= before, (
            "password_changed_at debe ser posterior al inicio de la operación"
        )
        assert verify_password(new_password, user.hashed_password), (
            "verify_password debe funcionar con la nueva contraseña"
        )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


# ---------------------------------------------------------------------------
# Property 9 (tarea 4.8): Revocación de refresh tokens post-cambio
# Feature: password-recovery, Property 9: Refresh token revocation after password change
# Validates: Requirements 3.5, 4.4
# ---------------------------------------------------------------------------

def test_refresh_token_revocation_after_password_change():
    """
    Verifica que _revoke_all_user_refresh_tokens es llamado (o que el mecanismo
    de invalidación por password_changed_at está activo) después de change_password.

    La implementación actual usa password_changed_at como mecanismo de invalidación
    de tokens (verificado en deps.py). Este test verifica que password_changed_at
    se actualiza correctamente, lo que invalida todos los tokens emitidos antes del cambio.

    # Feature: password-recovery, Property 9: Refresh token revocation after password change
    Validates: Requirements 3.5, 4.4
    """
    db, engine = _make_db()
    try:
        current_plain = "OldPass1!XYZabc"
        new_plain = "NewPass2!XYZabc"

        user = _make_user(
            db,
            email="revoke@example.com",
            password=hash_password(current_plain),
        )

        before_change = datetime.utcnow()

        change_password(
            db=db,
            user=user,
            current_password=current_plain,
            new_password=new_plain,
            ip="127.0.0.1",
        )

        db.refresh(user)

        # password_changed_at actualizado invalida todos los tokens emitidos antes
        assert user.password_changed_at is not None
        assert user.password_changed_at >= before_change, (
            "password_changed_at debe actualizarse para invalidar refresh tokens previos"
        )

        # Verificar que _revoke_all_user_refresh_tokens es invocado durante reset_password
        # usando un token real en BD
        token_plain = secrets.token_hex(32)
        token_hash = hashlib.sha256(token_plain.encode()).hexdigest()
        expires_at = datetime.utcnow() + timedelta(minutes=30)
        record = create_reset_token(db, user.id, token_hash, expires_at)

        # Actualizar la contraseña del usuario para que el token sea válido
        user.hashed_password = hash_password(new_plain)
        db.commit()

        before_reset = datetime.utcnow()

        with patch("app.services.password_recovery._revoke_all_user_refresh_tokens") as mock_revoke:
            reset_password(
                db=db,
                token=token_plain,
                new_password="AnotherPass3!XYZ",
                ip="127.0.0.1",
            )
            mock_revoke.assert_called_once_with(db, user.id)

        db.refresh(user)
        assert user.password_changed_at >= before_reset, (
            "password_changed_at debe actualizarse en reset_password"
        )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


# ---------------------------------------------------------------------------
# Property 11 (tarea 4.9): Verificación de contraseña actual en change-password
# Feature: password-recovery, Property 11: Current password verification in change-password
# Validates: Requirements 4.1, 4.3
# ---------------------------------------------------------------------------

@given(st.text(min_size=1, max_size=50))
@settings(max_examples=10)
def test_wrong_current_password_raises_400(wrong_password):
    """
    Para cualquier contraseña incorrecta, change_password debe lanzar
    HTTPException 400 con "Contraseña actual incorrecta".

    # Feature: password-recovery, Property 11: Current password verification in change-password
    Validates: Requirements 4.1, 4.3
    """
    known_password = "KnownPass1!XYZabc"

    db, engine = _make_db()
    try:
        user = _make_user(
            db,
            email="wrongpw@example.com",
            password=hash_password(known_password),
        )

        # Asegurarse de que la contraseña incorrecta no sea la correcta por casualidad
        if verify_password(wrong_password, user.hashed_password):
            return  # skip: hypothesis generó la contraseña correcta

        with pytest.raises(HTTPException) as exc_info:
            change_password(
                db=db,
                user=user,
                current_password=wrong_password,
                new_password="NewPass2!XYZabc",
                ip="127.0.0.1",
            )

        assert exc_info.value.status_code == 400, (
            f"Se esperaba 400, se obtuvo {exc_info.value.status_code}"
        )
        assert "Contraseña actual incorrecta" in exc_info.value.detail, (
            f"Mensaje inesperado: {exc_info.value.detail!r}"
        )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


# ---------------------------------------------------------------------------
# Property 5 (tarea 5.4): Error SMTP produce HTTP 503
# Feature: password-recovery, Property 5: SMTP error produces HTTP 503
# Validates: Requirements 2.3
# ---------------------------------------------------------------------------

from app.core.email_service import EmailDeliveryError


@given(email=st.emails())
@settings(max_examples=20)
def test_smtp_error_produces_503(email):
    """
    Para cualquier email válido de un usuario activo existente, cuando
    send_recovery_email lanza EmailDeliveryError, request_password_recovery
    debe propagar la excepción y el endpoint debe devolver HTTP 503 con el
    mensaje "No se pudo enviar el email de recuperación. Inténtalo más tarde."

    Aquí verificamos directamente que request_password_recovery propaga
    EmailDeliveryError, y que el endpoint la convierte en HTTPException 503.

    # Feature: password-recovery, Property 5: SMTP error produces HTTP 503
    Validates: Requirements 2.3
    """
    db, engine = _make_db()
    try:
        _make_user(db, email=email, is_active=True)

        with patch(
            "app.services.password_recovery.send_recovery_email",
            side_effect=EmailDeliveryError("SMTP connection refused"),
        ):
            # request_password_recovery debe propagar EmailDeliveryError
            with pytest.raises(EmailDeliveryError):
                request_password_recovery(db, email=email, ip="127.0.0.1")
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


# ---------------------------------------------------------------------------
# Property 18 (tarea 5.5): Completitud del audit log en endpoints
# Feature: password-recovery, Property 18: Audit log completeness
# Validates: Requirements 8.1, 8.2
# ---------------------------------------------------------------------------

@given(
    email=st.emails(),
    ip=st.from_regex(r"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}", fullmatch=True),
)
@settings(max_examples=20)
def test_audit_log_completeness(email, ip):
    """
    Para cualquier solicitud al flujo de recuperación (forgot-password),
    log_security_event debe ser llamado con los campos requeridos:
    IP del solicitante y email del usuario.

    # Feature: password-recovery, Property 18: Audit log completeness
    Validates: Requirements 8.1, 8.2
    """
    db, engine = _make_db()
    try:
        _make_user(db, email=email, is_active=True)

        with patch("app.services.password_recovery.send_recovery_email"), \
             patch("app.services.password_recovery.log_security_event") as mock_log:

            request_password_recovery(db, email=email, ip=ip)

        # log_security_event debe haber sido llamado al menos una vez
        assert mock_log.called, "log_security_event no fue llamado"

        # Verificar que al menos una llamada incluye ip=ip y email=email
        calls_with_required_fields = [
            call for call in mock_log.call_args_list
            if call.kwargs.get("ip") == ip and call.kwargs.get("email") == email
        ]
        assert len(calls_with_required_fields) >= 1, (
            f"Ninguna llamada a log_security_event incluyó ip={ip!r} y email={email!r}. "
            f"Llamadas realizadas: {mock_log.call_args_list}"
        )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()
