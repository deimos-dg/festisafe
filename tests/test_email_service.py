"""
Unit tests para EmailService.
Verifica: error SMTP, contenido del email, formato del deep link.
Requirements: 2.3, 2.4, 2.5
"""
import smtplib
import sys
from types import ModuleType
from unittest.mock import MagicMock, patch

import pytest

# ---------------------------------------------------------------------------
# Stub de settings para evitar que pydantic-settings exija variables de entorno
# al importar app.core.email_service en tiempo de colección.
# ---------------------------------------------------------------------------
_fake_settings = MagicMock()
_fake_settings.SMTP_HOST = "smtp.example.com"
_fake_settings.SMTP_PORT = 587
_fake_settings.SMTP_USER = ""
_fake_settings.SMTP_PASSWORD = ""
_fake_settings.SMTP_FROM = "noreply@example.com"
_fake_settings.APP_DEEP_LINK_BASE = ""

_config_stub = ModuleType("app.core.config")
_config_stub.settings = _fake_settings  # type: ignore[attr-defined]
sys.modules.setdefault("app.core.config", _config_stub)

from app.core.email_service import EmailDeliveryError, _build_recovery_email, send_recovery_email  # noqa: E402


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

FAKE_SETTINGS_BASE = {
    "SMTP_HOST": "smtp.example.com",
    "SMTP_PORT": 587,
    "SMTP_USER": "user@example.com",
    "SMTP_PASSWORD": "secret",
    "SMTP_FROM": "noreply@example.com",
    "APP_DEEP_LINK_BASE": "",
}


def _make_settings(**overrides):
    """Devuelve un MagicMock que simula `settings` con los valores dados."""
    s = MagicMock()
    cfg = {**FAKE_SETTINGS_BASE, **overrides}
    for k, v in cfg.items():
        setattr(s, k, v)
    return s


def _get_decoded_body(msg) -> str:
    """Extrae y decodifica el contenido de todas las partes del mensaje MIME."""
    parts = []
    for part in msg.walk():
        payload = part.get_payload(decode=True)
        if payload:
            parts.append(payload.decode("utf-8", errors="replace"))
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# 1. SMTP error → EmailDeliveryError
# ---------------------------------------------------------------------------

def test_smtp_error_raises_email_delivery_error():
    """Req 2.3: un error SMTP debe propagarse como EmailDeliveryError."""
    mock_settings = _make_settings()

    smtp_instance = MagicMock()
    smtp_instance.__enter__ = MagicMock(return_value=smtp_instance)
    smtp_instance.__exit__ = MagicMock(return_value=False)
    smtp_instance.sendmail.side_effect = smtplib.SMTPException("connection refused")

    with patch("app.core.email_service.settings", mock_settings), \
         patch("smtplib.SMTP", return_value=smtp_instance):
        with pytest.raises(EmailDeliveryError):
            send_recovery_email("Alice", "alice@example.com", "a" * 64)


# ---------------------------------------------------------------------------
# 2. El email contiene el nombre del usuario
# ---------------------------------------------------------------------------

def test_email_contains_user_name():
    """Req 2.4: el cuerpo del email debe incluir el nombre del usuario."""
    mock_settings = _make_settings()

    with patch("app.core.email_service.settings", mock_settings):
        msg = _build_recovery_email("Carlos", "carlos@example.com", "tok" + "x" * 61)

    assert "Carlos" in _get_decoded_body(msg)


# ---------------------------------------------------------------------------
# 3. El email contiene el token
# ---------------------------------------------------------------------------

def test_email_contains_token():
    """Req 2.4: el cuerpo del email debe incluir el token de recuperación."""
    token = "b" * 64
    mock_settings = _make_settings()

    with patch("app.core.email_service.settings", mock_settings):
        msg = _build_recovery_email("Bob", "bob@example.com", token)

    assert token in _get_decoded_body(msg)


# ---------------------------------------------------------------------------
# 4. El email menciona los 30 minutos de expiración
# ---------------------------------------------------------------------------

def test_email_contains_expiry_minutes():
    """Req 2.4: el email debe indicar que el código expira en 30 minutos."""
    mock_settings = _make_settings()

    with patch("app.core.email_service.settings", mock_settings):
        msg = _build_recovery_email("Diana", "diana@example.com", "c" * 64)

    assert "30" in _get_decoded_body(msg)


# ---------------------------------------------------------------------------
# 5. Deep link cuando APP_DEEP_LINK_BASE está configurado
# ---------------------------------------------------------------------------

def test_deep_link_format_when_configured():
    """Req 2.5: cuando APP_DEEP_LINK_BASE está configurado el email debe
    contener el enlace con formato {base}/reset-password?token={token}."""
    token = "d" * 64
    base = "festisafe://"
    mock_settings = _make_settings(APP_DEEP_LINK_BASE=base)

    with patch("app.core.email_service.settings", mock_settings):
        msg = _build_recovery_email("Eve", "eve@example.com", token)

    expected_link = f"{base}/reset-password?token={token}"
    assert expected_link in _get_decoded_body(msg)


# ---------------------------------------------------------------------------
# 6. Sin deep link cuando APP_DEEP_LINK_BASE está vacío
# ---------------------------------------------------------------------------

def test_no_deep_link_when_not_configured():
    """Req 2.5: cuando APP_DEEP_LINK_BASE está vacío no debe aparecer
    ningún enlace de tipo reset-password en el email."""
    token = "e" * 64
    mock_settings = _make_settings(APP_DEEP_LINK_BASE="")

    with patch("app.core.email_service.settings", mock_settings):
        msg = _build_recovery_email("Frank", "frank@example.com", token)

    assert "reset-password?token=" not in _get_decoded_body(msg)
