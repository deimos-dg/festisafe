"""
Servicio de email transaccional vía SMTP con TLS.
Usado para enviar tokens de recuperación de contraseña.
"""
import smtplib
import logging
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.core.config import settings

logger = logging.getLogger(__name__)

TOKEN_EXPIRY_MINUTES = 30


class EmailDeliveryError(Exception):
    """Se lanza cuando el envío de email falla por error SMTP."""
    pass


def _build_recovery_email(
    user_name: str,
    user_email: str,
    token: str,
) -> MIMEMultipart:
    msg = MIMEMultipart("alternative")
    msg["Subject"] = "Recuperación de contraseña — FestiSafe"
    msg["From"] = settings.SMTP_FROM
    msg["To"] = user_email

    deep_link = ""
    if settings.APP_DEEP_LINK_BASE:
        deep_link = f"{settings.APP_DEEP_LINK_BASE}/reset-password?token={token}"

    plain = (
        f"Hola {user_name},\n\n"
        f"Recibimos una solicitud para restablecer tu contraseña en FestiSafe.\n\n"
        f"Tu código de recuperación es:\n\n"
        f"  {token}\n\n"
        f"Este código expira en {TOKEN_EXPIRY_MINUTES} minutos.\n\n"
    )
    if deep_link:
        plain += f"O abre este enlace directamente:\n  {deep_link}\n\n"
    plain += (
        "Si no solicitaste este cambio, ignora este mensaje. "
        "Tu contraseña actual seguirá siendo válida.\n\n"
        "— El equipo de FestiSafe"
    )

    html = f"""
    <html><body style="font-family:sans-serif;max-width:480px;margin:auto;padding:24px">
      <h2 style="color:#1a1a2e">Recuperación de contraseña</h2>
      <p>Hola <strong>{user_name}</strong>,</p>
      <p>Recibimos una solicitud para restablecer tu contraseña en FestiSafe.</p>
      <p>Tu código de recuperación es:</p>
      <div style="background:#f4f4f8;border-radius:8px;padding:16px;text-align:center;
                  font-size:18px;font-family:monospace;letter-spacing:2px;margin:16px 0">
        {token}
      </div>
      <p style="color:#666;font-size:13px">
        Este código expira en <strong>{TOKEN_EXPIRY_MINUTES} minutos</strong>.
      </p>
    """
    if deep_link:
        html += f"""
      <p>
        <a href="{deep_link}"
           style="display:inline-block;background:#6c63ff;color:#fff;padding:12px 24px;
                  border-radius:8px;text-decoration:none;font-weight:bold">
          Restablecer contraseña
        </a>
      </p>
        """
    html += """
      <hr style="border:none;border-top:1px solid #eee;margin:24px 0">
      <p style="color:#999;font-size:12px">
        Si no solicitaste este cambio, ignora este mensaje.
        Tu contraseña actual seguirá siendo válida.
      </p>
    </body></html>
    """

    msg.attach(MIMEText(plain, "plain"))
    msg.attach(MIMEText(html, "html"))
    return msg


def send_recovery_email(user_name: str, user_email: str, token: str) -> None:
    """
    Envía el email de recuperación de contraseña.
    Lanza EmailDeliveryError si el envío falla.
    """
    if not settings.SMTP_HOST:
        logger.warning("Email: SMTP_HOST no configurado — email de recuperación no enviado")
        raise EmailDeliveryError("SMTP no configurado")

    msg = _build_recovery_email(user_name, user_email, token)

    try:
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=10) as server:
            server.ehlo()
            server.starttls()
            server.ehlo()
            if settings.SMTP_USER:
                server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            server.sendmail(settings.SMTP_FROM, [user_email], msg.as_string())
        logger.info(f"Email: recuperación enviada a {user_email}")
    except smtplib.SMTPException as e:
        logger.error(f"Email: error SMTP al enviar a {user_email}: {e}")
        raise EmailDeliveryError(str(e)) from e
    except OSError as e:
        logger.error(f"Email: error de red al conectar a SMTP: {e}")
        raise EmailDeliveryError(str(e)) from e
