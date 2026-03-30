# Feature: password-recovery, Property 12: Token validity invariant
"""
Property-based tests for PasswordResetToken.is_valid() invariant.
Validates: Requirements 5.2
"""

from datetime import datetime

from hypothesis import given, settings
from hypothesis import strategies as st

from app.db.models.password_reset_token import PasswordResetToken


# **Validates: Requirements 5.2**
@given(
    expires_at=st.datetimes(),
    used_at=st.one_of(st.none(), st.datetimes()),
)
@settings(max_examples=100)
def test_token_validity_invariant(expires_at: datetime, used_at):
    """
    Para cualquier PasswordResetToken, is_valid() debe retornar True si y solo si
    used_at IS NULL AND expires_at > datetime.utcnow().
    """
    token = PasswordResetToken(expires_at=expires_at, used_at=used_at)

    expected = used_at is None and expires_at > datetime.utcnow()
    assert token.is_valid() == expected
