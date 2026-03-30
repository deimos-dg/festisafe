"""
Logging de auditoría de seguridad.
Registra eventos críticos: logins, fallos de auth, cambios de rol, SOS, etc.
"""
import logging
import json
from datetime import datetime
from enum import Enum
from typing import Optional

# Logger dedicado a seguridad — separado del logger general
security_logger = logging.getLogger("festisafe.security")


class AuditEvent(str, Enum):
    LOGIN_SUCCESS = "LOGIN_SUCCESS"
    LOGIN_FAILED = "LOGIN_FAILED"
    LOGIN_BLOCKED = "LOGIN_BLOCKED"
    LOGOUT = "LOGOUT"
    REGISTER = "REGISTER"
    GUEST_LOGIN = "GUEST_LOGIN"
    TOKEN_REFRESH = "TOKEN_REFRESH"
    TOKEN_REVOKED = "TOKEN_REVOKED"
    PASSWORD_CHANGED = "PASSWORD_CHANGED"
    ROLE_CHANGED = "ROLE_CHANGED"
    ACCOUNT_LOCKED = "ACCOUNT_LOCKED"
    ACCOUNT_UNLOCKED = "ACCOUNT_UNLOCKED"
    SOS_ACTIVATED = "SOS_ACTIVATED"
    SOS_DEACTIVATED = "SOS_DEACTIVATED"
    SOS_ESCALATED = "SOS_ESCALATED"
    EVENT_CREATED = "EVENT_CREATED"
    EVENT_DELETED = "EVENT_DELETED"
    UNAUTHORIZED_ACCESS = "UNAUTHORIZED_ACCESS"
    RATE_LIMIT_HIT = "RATE_LIMIT_HIT"
    INVALID_TOKEN = "INVALID_TOKEN"
    PASSWORD_RESET_REQUESTED = "PASSWORD_RESET_REQUESTED"
    PASSWORD_RESET_FAILED = "PASSWORD_RESET_FAILED"
    BRUTE_FORCE_DETECTED = "BRUTE_FORCE_DETECTED"


def log_security_event(
    event: AuditEvent,
    ip: Optional[str] = None,
    user_id: Optional[str] = None,
    email: Optional[str] = None,
    detail: Optional[str] = None,
    extra: Optional[dict] = None,
) -> None:
    """
    Registra un evento de seguridad en formato JSON estructurado.
    Facilita la ingesta en SIEM (Splunk, ELK, CloudWatch Logs Insights).
    """
    record = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "event": event.value,
        "ip": ip or "unknown",
        "user_id": user_id,
        "email": email,
        "detail": detail,
    }
    if extra:
        record.update(extra)

    # Nivel WARNING para eventos de fallo, INFO para éxito
    failed_events = {
        AuditEvent.LOGIN_FAILED,
        AuditEvent.LOGIN_BLOCKED,
        AuditEvent.UNAUTHORIZED_ACCESS,
        AuditEvent.RATE_LIMIT_HIT,
        AuditEvent.INVALID_TOKEN,
        AuditEvent.ACCOUNT_LOCKED,
        AuditEvent.PASSWORD_RESET_FAILED,
        AuditEvent.BRUTE_FORCE_DETECTED,
    }
    level = logging.WARNING if event in failed_events else logging.INFO
    security_logger.log(level, json.dumps(record, ensure_ascii=False))
