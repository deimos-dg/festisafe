import logging
from sqlalchemy import text
from app.db.session import SessionLocal, engine, get_db  # noqa: F401 — re-export get_db
from app.db.base import Base  # noqa: F401 — importar Base con todos los modelos registrados
import app.db.models  # noqa: F401 — asegura que todos los modelos estén cargados

logger = logging.getLogger(__name__)


def create_tables():
    Base.metadata.create_all(bind=engine)
    logger.info("Tablas creadas exitosamente")
    _run_migrations()


def _run_migrations():
    """Migraciones manuales para columnas agregadas después del deploy inicial."""
    migrations = [
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS is_guest BOOLEAN NOT NULL DEFAULT FALSE",
        "CREATE INDEX IF NOT EXISTS ix_users_is_guest ON users (is_guest)",
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW()",
        "CREATE INDEX IF NOT EXISTS ix_revoked_tokens_revoked_at ON revoked_tokens (revoked_at)",
        # password_reset_tokens — recuperación de contraseña
        """CREATE TABLE IF NOT EXISTS password_reset_tokens (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            token_hash VARCHAR(64) UNIQUE NOT NULL,
            expires_at TIMESTAMP NOT NULL,
            used_at TIMESTAMP,
            created_at TIMESTAMP NOT NULL DEFAULT NOW()
        )""",
        "CREATE INDEX IF NOT EXISTS ix_prt_user_id ON password_reset_tokens (user_id)",
        "CREATE INDEX IF NOT EXISTS ix_prt_token_hash ON password_reset_tokens (token_hash)",
        "CREATE INDEX IF NOT EXISTS ix_prt_expires_at ON password_reset_tokens (expires_at)",
        "CREATE INDEX IF NOT EXISTS ix_prt_user_active ON password_reset_tokens (user_id, expires_at)",
    ]
    with engine.connect() as conn:
        for sql in migrations:
            try:
                conn.execute(text(sql))
                logger.info(f"Migración aplicada: {sql[:60]}...")
            except Exception as e:
                logger.warning(f"Migración omitida ({sql[:40]}...): {e}")
        conn.commit()
