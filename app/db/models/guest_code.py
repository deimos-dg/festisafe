import uuid
from datetime import datetime

from sqlalchemy import Column, String, DateTime, Boolean, ForeignKey, Integer, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class GuestCode(Base):
    __tablename__ = "guest_codes"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    code = Column(String(6), unique=True, nullable=False, index=True)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id", ondelete="CASCADE"), nullable=False, index=True)
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    max_uses = Column(Integer, default=1)
    used_count = Column(Integer, default=0)
    expires_at = Column(DateTime, nullable=False, index=True)
    is_active = Column(Boolean, default=True, index=True)

    created_at = Column(DateTime, default=datetime.utcnow)

    event = relationship("Event", foreign_keys=[event_id])
    creator = relationship("User", foreign_keys=[created_by])

    __table_args__ = (
        Index("ix_guest_code_active", "code", "is_active", "expires_at"),
    )

    @property
    def remaining_uses(self) -> int:
        return max(0, self.max_uses - self.used_count)

    def is_valid(self) -> bool:
        return (
            self.is_active
            and self.remaining_uses > 0
            and self.expires_at > datetime.utcnow()
        )
