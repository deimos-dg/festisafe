from sqlalchemy.orm import Session
from app.db.models.revoked_token import RevokedToken


def revoke_token(jti: str, db: Session):
    token = RevokedToken(jti=jti)
    db.add(token)
    db.commit()


def is_token_revoked(db: Session, jti: str) -> bool:
    """Orden consistente con crud/token.py: (db, jti)."""
    return db.query(RevokedToken).filter_by(jti=jti).first() is not None