from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from typing import Generator

from app.core.config import settings

# Pool configurado para prevenir agotamiento de conexiones (DoS a nivel BD)
engine = create_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    pool_pre_ping=True,
    pool_size=10,          # Conexiones persistentes en el pool
    max_overflow=20,       # Conexiones extra permitidas bajo carga
    pool_timeout=30,       # Segundos de espera antes de lanzar error
    pool_recycle=1800,     # Reciclar conexiones cada 30 min (evita stale connections)
)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
)


def get_db() -> Generator:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
