"""
Property tests para completitud del contenido del email de recuperación.

# Feature: password-recovery, Property 6: Email content completeness
# Validates: Requirements 2.4, 2.5
"""
import os
import sys

# Proveer variables de entorno requeridas antes de importar settings
os.environ.setdefault("SECRET_KEY", "test-secret-key-at-least-32-characters-long")
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import email
from unittest.mock import MagicMock, patch

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from app.core.email_service import _build_recovery_email


# Estrategia: nombres de usuario con texto imprimible no vacío
user_name_strategy = st.text(
    alphabet=st.characters(whitelist_categories=("Lu", "Ll", "Nd"), whitelist_characters=" "),
    min_size=1,
    max_size=50,
).filter(lambda s: s.strip())

# Estrategia: tokens hex de 64 caracteres (32 bytes)
token_strategy = st.binary(min_size=32, max_size=32).map(lambda b: b.hex())

# Estrategia: emails válidos
email_strategy = st.emails()


# Feature: password-recovery, Property 6: Email content completeness
# Validates: Requirements 2.4, 2.5
@given(user_name=user_name_strategy, token=token_strategy, user_email=email_strategy)
@settings(max_examples=20)
def test_email_contains_user_name_token_and_expiry(user_name, token, user_email):
    """
    Para cualquier usuario y Recovery_Token, el email generado debe contener:
    - el nombre del usuario
    - el token
    - la indicación de expiración en 30 minutos

    Validates: Requirements 2.4, 2.5
    """
    with patch("app.core.email_service.settings") as mock_settings:
        mock_settings.SMTP_FROM = "noreply@festisafe.com"
        mock_settings.APP_DEEP_LINK_BASE = ""  # sin deep link

        msg = _build_recovery_email(user_name, user_email, token)

    # Extraer el cuerpo del mensaje (parte plain text)
    body_plain = ""
    body_html = ""
    for part in msg.walk():
        content_type = part.get_content_type()
        payload = part.get_payload(decode=True)
        if payload is None:
            continue
        decoded = payload.decode("utf-8", errors="replace")
        if content_type == "text/plain":
            body_plain = decoded
        elif content_type == "text/html":
            body_html = decoded

    # El nombre del usuario debe aparecer en el cuerpo
    assert user_name in body_plain, f"Nombre '{user_name}' no encontrado en el cuerpo plain"
    assert user_name in body_html, f"Nombre '{user_name}' no encontrado en el cuerpo HTML"

    # El token debe aparecer en el cuerpo
    assert token in body_plain, f"Token no encontrado en el cuerpo plain"
    assert token in body_html, f"Token no encontrado en el cuerpo HTML"

    # La indicación de expiración en 30 minutos debe aparecer
    assert "30" in body_plain, "Indicación de 30 minutos no encontrada en el cuerpo plain"
    assert "30" in body_html, "Indicación de 30 minutos no encontrada en el cuerpo HTML"


# Feature: password-recovery, Property 6: Email content completeness (deep link)
# Validates: Requirements 2.5
@given(
    user_name=user_name_strategy,
    token=token_strategy,
    user_email=email_strategy,
    base_url=st.from_regex(r"https?://[a-z]{3,10}\.[a-z]{2,4}", fullmatch=True),
)
@settings(max_examples=100)
def test_email_deep_link_format_when_configured(user_name, token, user_email, base_url):
    """
    Si APP_DEEP_LINK_BASE está configurado, el enlace en el email debe seguir
    el formato {APP_DEEP_LINK_BASE}/reset-password?token={token}.

    Validates: Requirements 2.5
    """
    expected_link = f"{base_url}/reset-password?token={token}"

    with patch("app.core.email_service.settings") as mock_settings:
        mock_settings.SMTP_FROM = "noreply@festisafe.com"
        mock_settings.APP_DEEP_LINK_BASE = base_url

        msg = _build_recovery_email(user_name, user_email, token)

    body_plain = ""
    body_html = ""
    for part in msg.walk():
        content_type = part.get_content_type()
        payload = part.get_payload(decode=True)
        if payload is None:
            continue
        decoded = payload.decode("utf-8", errors="replace")
        if content_type == "text/plain":
            body_plain = decoded
        elif content_type == "text/html":
            body_html = decoded

    assert expected_link in body_plain, (
        f"Deep link '{expected_link}' no encontrado en el cuerpo plain"
    )
    assert expected_link in body_html, (
        f"Deep link '{expected_link}' no encontrado en el cuerpo HTML"
    )


# Feature: password-recovery, Property 6: Email content completeness (send path)
# Validates: Requirements 2.4
@given(user_name=user_name_strategy, token=token_strategy, user_email=email_strategy)
@settings(max_examples=100)
def test_send_recovery_email_delivers_complete_content(user_name, token, user_email):
    """
    Al llamar a send_recovery_email, el mensaje enviado vía smtplib debe contener
    el nombre del usuario, el token y la indicación de expiración en 30 minutos.
    Se parsea el mensaje MIME para decodificar partes base64.

    Validates: Requirements 2.4
    """
    import email as email_module

    captured_messages = []

    mock_smtp_instance = MagicMock()

    def capture_sendmail(from_addr, to_addrs, msg_string):
        captured_messages.append(msg_string)

    mock_smtp_instance.sendmail.side_effect = capture_sendmail
    mock_smtp_instance.__enter__ = lambda s: s
    mock_smtp_instance.__exit__ = MagicMock(return_value=False)

    with patch("app.core.email_service.settings") as mock_settings, \
         patch("smtplib.SMTP", return_value=mock_smtp_instance):

        mock_settings.SMTP_HOST = "smtp.example.com"
        mock_settings.SMTP_PORT = 587
        mock_settings.SMTP_USER = ""
        mock_settings.SMTP_PASSWORD = ""
        mock_settings.SMTP_FROM = "noreply@festisafe.com"
        mock_settings.APP_DEEP_LINK_BASE = ""

        from app.core.email_service import send_recovery_email
        send_recovery_email(user_name, user_email, token)

    assert len(captured_messages) == 1, "Se esperaba exactamente un mensaje enviado"

    # Parsear el mensaje MIME para decodificar partes (pueden estar en base64)
    parsed = email_module.message_from_string(captured_messages[0])
    body_text = ""
    for part in parsed.walk():
        payload = part.get_payload(decode=True)
        if payload is not None:
            body_text += payload.decode("utf-8", errors="replace")

    assert user_name in body_text, f"Nombre '{user_name}' no encontrado en el mensaje enviado"
    assert token in body_text, "Token no encontrado en el mensaje enviado"
    assert "30" in body_text, "Indicación de 30 minutos no encontrada en el mensaje enviado"
