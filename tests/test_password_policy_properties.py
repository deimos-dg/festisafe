# Feature: password-recovery, Property 10: Password policy enforcement
"""
Property tests para la política de contraseñas en los schemas
ResetPasswordRequest y ChangePasswordRequest.

Validates: Requirements 3.4
"""
import pytest
from hypothesis import given, settings, assume
from hypothesis import strategies as st
from pydantic import ValidationError

from app.schemas.auth import ResetPasswordRequest, ChangePasswordRequest


# ---------------------------------------------------------------------------
# Estrategias de generación de contraseñas inválidas
# ---------------------------------------------------------------------------

# Contraseña demasiado corta (1–11 chars), con cualquier contenido
_short_password = st.text(
    alphabet=st.characters(
        whitelist_categories=("Lu", "Ll", "Nd"),
        whitelist_characters="!@#$%^&*()",
    ),
    min_size=1,
    max_size=11,
)

# Contraseña larga pero sin mayúsculas
_no_uppercase = st.text(
    alphabet=st.characters(
        whitelist_categories=("Ll", "Nd"),
        whitelist_characters="!@#$%^&*()",
    ),
    min_size=12,
    max_size=40,
).filter(lambda s: bool(s))

# Contraseña larga pero sin minúsculas
_no_lowercase = st.text(
    alphabet=st.characters(
        whitelist_categories=("Lu", "Nd"),
        whitelist_characters="!@#$%^&*()",
    ),
    min_size=12,
    max_size=40,
).filter(lambda s: bool(s))

# Contraseña larga pero sin dígitos
_no_digit = st.text(
    alphabet=st.characters(
        whitelist_categories=("Lu", "Ll"),
        whitelist_characters="!@#$%^&*()",
    ),
    min_size=12,
    max_size=40,
).filter(lambda s: bool(s))

# Contraseña larga pero sin caracteres especiales (solo letras y dígitos)
_no_special = st.text(
    alphabet=st.characters(
        whitelist_categories=("Lu", "Ll", "Nd"),
    ),
    min_size=12,
    max_size=40,
).filter(lambda s: bool(s))


def invalid_password_strategy():
    """Genera contraseñas que violan al menos una regla de validate_password."""
    return st.one_of(
        _short_password,
        _no_uppercase,
        _no_lowercase,
        _no_digit,
        _no_special,
    )


# Token hex de 64 chars válido para ResetPasswordRequest
_valid_token = st.text(
    alphabet="0123456789abcdef",
    min_size=64,
    max_size=64,
)


# ---------------------------------------------------------------------------
# Property 10a: ResetPasswordRequest rechaza contraseñas inválidas
# ---------------------------------------------------------------------------

# Feature: password-recovery, Property 10: Password policy enforcement
@given(token=_valid_token, bad_password=invalid_password_strategy())
@settings(max_examples=200)
def test_reset_password_rejects_invalid_password(token: str, bad_password: str):
    """
    Para cualquier string que no cumpla validate_password,
    ResetPasswordRequest debe lanzar ValidationError.

    Validates: Requirements 3.4
    """
    with pytest.raises(ValidationError):
        ResetPasswordRequest(
            token=token,
            new_password=bad_password,
            confirm_password=bad_password,
        )


# ---------------------------------------------------------------------------
# Property 10b: ChangePasswordRequest rechaza contraseñas inválidas
# ---------------------------------------------------------------------------

# Feature: password-recovery, Property 10: Password policy enforcement
@given(bad_password=invalid_password_strategy())
@settings(max_examples=200)
def test_change_password_rejects_invalid_password(bad_password: str):
    """
    Para cualquier string que no cumpla validate_password,
    ChangePasswordRequest debe lanzar ValidationError.

    Validates: Requirements 3.4
    """
    with pytest.raises(ValidationError):
        ChangePasswordRequest(
            current_password="cualquier_valor",
            new_password=bad_password,
            confirm_password=bad_password,
        )
