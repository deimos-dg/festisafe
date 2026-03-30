from datetime import datetime, timedelta
from sqlalchemy.orm import Session

from app.db.models.password_reset_token import PasswordResetToken


def create_reset_token(
    db: Session,
    user_id,
    token_hash: str,
    expires_at: datetime,
) -> PasswordResetToken:
    record = PasswordResetToken(
        user_id=user_id,
        token_hash=token_hash,
        expires_at=expires_at,
    )
    db.add(record)
    db.commit()
    db.refresh(record)
    return record


def get_token_by_hash(db: Session, token_hash: str) -> PasswordResetToken | None:
    return db.query(PasswordResetToken).filter(
        PasswordResetToken.token_hash == token_hash
    ).first()


def invalidate_user_tokens(db: Session, user_id) -> None:
    """Marca como usados todos los tokens activos del usuario."""
    now = datetime.utcnow()
    db.query(PasswordResetToken).filter(
        PasswordResetToken.user_id == user_id,
        PasswordResetToken.used_at.is_(None),
        PasswordResetToken.expires_at > now,
    ).update({"used_at": now}, synchronize_session=False)
    db.commit()


def cleanup_expired_tokens(db: Session) -> int:
    """Elimina tokens con expires_at anterior a hace 24 horas. Retorna el número eliminado."""
    cutoff = datetime.utcnow() - timedelta(hours=24)
    deleted = db.query(PasswordResetToken).filter(
        PasswordResetToken.expires_at < cutoff
    ).delete(synchronize_session=False)
    db.commit()
    return deleted
