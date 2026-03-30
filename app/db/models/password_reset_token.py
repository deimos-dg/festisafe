import uuid
from datetime import datetime

from sqlalchemy import Column, String, DateTime, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id    = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    token_hash = Column(String(64), unique=True, nullable=False, index=True)  # SHA-256 hex
    expires_at = Column(DateTime, nullable=False, index=True)
    used_at    = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="password_reset_tokens")

    __table_args__ = (
        Index("ix_prt_user_active", "user_id", "expires_at"),
    )

    def is_valid(self) -> bool:
        """Un token es válido si no ha sido usado y no ha expirado."""
        return self.used_at is None and self.expires_at > datetime.utcnow()
