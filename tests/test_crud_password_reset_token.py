"""
Unit tests para CRUD de PasswordResetToken.
Validates: Requirements 5.1, 5.3, 5.4
"""
import uuid
from datetime import datetime, timedelta

import pytest

from app.crud.password_reset_token import (
    cleanup_expired_tokens,
    create_reset_token,
    get_token_by_hash,
    invalidate_user_tokens,
)
from app.db.models.password_reset_token import PasswordResetToken


# ---------------------------------------------------------------------------
# 1. Creación
# ---------------------------------------------------------------------------

def test_create_reset_token(db, sample_user):
    """Crear un token y verificar que se almacena correctamente. (Req 5.1)"""
    token_hash = "a" * 64
    expires_at = datetime.utcnow() + timedelta(minutes=30)

    record = create_reset_token(db, sample_user.id, token_hash, expires_at)

    assert record.id is not None
    assert record.user_id == sample_user.id
    assert record.token_hash == token_hash
    assert record.expires_at == expires_at
    assert record.used_at is None
    assert record.created_at is not None


# ---------------------------------------------------------------------------
# 2. Lookup por hash
# ---------------------------------------------------------------------------

def test_get_token_by_hash_found(db, sample_user):
    """Buscar por hash existente retorna el token correcto. (Req 5.1)"""
    token_hash = "b" * 64
    expires_at = datetime.utcnow() + timedelta(minutes=30)
    create_reset_token(db, sample_user.id, token_hash, expires_at)

    result = get_token_by_hash(db, token_hash)

    assert result is not None
    assert result.token_hash == token_hash
    assert result.user_id == sample_user.id


def test_get_token_by_hash_not_found(db):
    """Buscar por hash inexistente retorna None. (Req 5.1)"""
    result = get_token_by_hash(db, "0" * 64)

    assert result is None


# ---------------------------------------------------------------------------
# 3. Invalidación
# ---------------------------------------------------------------------------

def test_invalidate_user_tokens(db, sample_user):
    """Después de invalidar, los tokens activos del usuario tienen used_at no nulo. (Req 5.3)"""
    expires_at = datetime.utcnow() + timedelta(minutes=30)
    token1 = create_reset_token(db, sample_user.id, "c" * 64, expires_at)
    token2 = create_reset_token(db, sample_user.id, "d" * 64, expires_at)

    invalidate_user_tokens(db, sample_user.id)

    db.refresh(token1)
    db.refresh(token2)
    assert token1.used_at is not None
    assert token2.used_at is not None


def test_invalidate_user_tokens_does_not_affect_other_users(db, sample_user):
    """Invalidar tokens de un usuario no afecta los tokens de otro usuario."""
    from app.db.models.user import User

    other_user = User(
        id=uuid.uuid4(),
        email="other@example.com",
        hashed_password="hashed_pw",
        name="Other User",
        is_active=True,
    )
    db.add(other_user)
    db.commit()

    expires_at = datetime.utcnow() + timedelta(minutes=30)
    other_token = create_reset_token(db, other_user.id, "e" * 64, expires_at)

    invalidate_user_tokens(db, sample_user.id)

    db.refresh(other_token)
    assert other_token.used_at is None


# ---------------------------------------------------------------------------
# 4. Limpieza de tokens expirados
# ---------------------------------------------------------------------------

def test_cleanup_expired_tokens_removes_old_tokens(db, sample_user):
    """Tokens con expires_at < now-24h son eliminados. (Req 5.4)"""
    old_expires = datetime.utcnow() - timedelta(hours=25)
    old_token = create_reset_token(db, sample_user.id, "f" * 64, old_expires)
    old_id = old_token.id

    deleted = cleanup_expired_tokens(db)

    assert deleted >= 1
    assert db.query(PasswordResetToken).filter_by(id=old_id).first() is None


def test_cleanup_expired_tokens_keeps_recent_tokens(db, sample_user):
    """Tokens recientes (expires_at >= now-24h) permanecen intactos. (Req 5.4)"""
    recent_expires = datetime.utcnow() + timedelta(minutes=30)
    recent_token = create_reset_token(db, sample_user.id, "g" * 64, recent_expires)
    recent_id = recent_token.id

    cleanup_expired_tokens(db)

    assert db.query(PasswordResetToken).filter_by(id=recent_id).first() is not None


def test_cleanup_expired_tokens_mixed(db, sample_user):
    """Solo se eliminan los tokens viejos; los recientes sobreviven. (Req 5.4)"""
    old_expires = datetime.utcnow() - timedelta(hours=25)
    recent_expires = datetime.utcnow() + timedelta(minutes=30)

    old_token = create_reset_token(db, sample_user.id, "h" * 64, old_expires)
    recent_token = create_reset_token(db, sample_user.id, "i" * 64, recent_expires)

    # Guardar IDs antes del DELETE para evitar ObjectDeletedError al acceder al objeto
    old_id = old_token.id
    recent_id = recent_token.id

    deleted = cleanup_expired_tokens(db)

    assert deleted == 1
    assert db.query(PasswordResetToken).filter_by(id=old_id).first() is None
    assert db.query(PasswordResetToken).filter_by(id=recent_id).first() is not None
