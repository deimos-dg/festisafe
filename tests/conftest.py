"""
Fixtures compartidos para los tests de password-recovery.
Usa SQLite en memoria para no depender de la BD real de la aplicación.
"""
import uuid
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.db.base import Base

# Importar todos los modelos para que Base.metadata los registre
from app.db.models.user import User  # noqa: F401
from app.db.models.password_reset_token import PasswordResetToken  # noqa: F401


@pytest.fixture(scope="function")
def db():
    """Sesión SQLite en memoria, aislada por test."""
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(engine)
        engine.dispose()


@pytest.fixture(scope="function")
def sample_user(db):
    """Usuario de prueba persistido en la BD en memoria."""
    user = User(
        id=uuid.uuid4(),
        email="test@example.com",
        hashed_password="hashed_pw",
        name="Test User",
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user
