"""
Property tests para el scheduler de limpieza de tokens expirados.

Cubre la propiedad 13 del diseño técnico.
"""
import os
import uuid
from datetime import datetime, timedelta

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Proveer variables de entorno requeridas antes de importar settings
os.environ.setdefault("SECRET_KEY", "test-secret-key-at-least-32-characters-long")
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from app.db.base import Base
from app.db.models.user import User
from app.db.models.password_reset_token import PasswordResetToken
from app.crud.password_reset_token import cleanup_expired_tokens


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


def _make_user(db, email="user@example.com"):
    user = User(
        id=uuid.uuid4(),
        email=email,
        hashed_password="hashed_pw",
        name="Test User",
        is_active=True,
        must_change_password=False,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _make_token(db, user_id, age_hours: float) -> PasswordResetToken:
    """Crea un token cuyo expires_at = now - age_hours."""
    now = datetime.utcnow()
    expires_at = now - timedelta(hours=age_hours)
    token = PasswordResetToken(
        id=uuid.uuid4(),
        user_id=user_id,
        token_hash=uuid.uuid4().hex + uuid.uuid4().hex,  # 64-char unique hash
        expires_at=expires_at,
    )
    db.add(token)
    db.commit()
    db.refresh(token)
    return token


# ---------------------------------------------------------------------------
# Property 13: Limpieza de tokens expirados por scheduler
# Feature: password-recovery, Property 13: Expired token cleanup by scheduler
# Validates: Requirements 5.4
# ---------------------------------------------------------------------------

# Estrategia: lista de edades en horas (algunas > 24h, algunas <= 24h)
_token_ages_strategy = st.lists(
    st.floats(min_value=0.0, max_value=72.0, allow_nan=False, allow_infinity=False),
    min_size=1,
    max_size=10,
)


@given(age_hours_list=_token_ages_strategy)
@settings(max_examples=20)
def test_expired_token_cleanup_by_scheduler(age_hours_list):
    """
    Para cualquier conjunto de tokens en password_reset_tokens, después de
    ejecutar cleanup_expired_tokens(db), todos los tokens con
    expires_at < now - 24 horas deben haber sido eliminados, y los tokens
    con expires_at >= now - 24 horas deben permanecer intactos.

    # Feature: password-recovery, Property 13: Expired token cleanup by scheduler
    Validates: Requirements 5.4
    """
    db, engine = _make_db()
    try:
        user = _make_user(db)

        # Crear tokens con las edades generadas
        token_ids = []
        for age_hours in age_hours_list:
            token = _make_token(db, user.id, age_hours)
            token_ids.append((token.id, age_hours))

        # Ejecutar la limpieza
        cleanup_expired_tokens(db)

        # Verificar invariantes
        cutoff = datetime.utcnow() - timedelta(hours=24)

        for token_id, age_hours in token_ids:
            remaining = db.query(PasswordResetToken).filter(
                PasswordResetToken.id == token_id
            ).first()

            # expires_at = now - age_hours; debe eliminarse si age_hours > 24
            # (es decir, expires_at < now - 24h = cutoff)
            should_be_deleted = age_hours > 24.0

            if should_be_deleted:
                assert remaining is None, (
                    f"Token con age_hours={age_hours:.2f} (expires_at < cutoff) "
                    f"debería haber sido eliminado pero sigue en BD"
                )
            else:
                assert remaining is not None, (
                    f"Token con age_hours={age_hours:.2f} (expires_at >= cutoff) "
                    f"no debería haber sido eliminado pero ya no está en BD"
                )
    finally:
        db.close()
        Base.metadata.drop_all(engine)
        engine.dispose()
