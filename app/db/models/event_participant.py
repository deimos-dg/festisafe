import uuid
from datetime import datetime

from sqlalchemy import (
    Column, String, DateTime, Boolean,
    ForeignKey, Float, UniqueConstraint, Index,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class EventParticipant(Base):
    __tablename__ = "event_participants"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)

    # FK tipado como UUID para coincidir con users.id y events.id
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id", ondelete="CASCADE"), nullable=False, index=True)

    role = Column(String(30), default="attendee", nullable=False)
    is_active = Column(Boolean, default=True, nullable=False, index=True)

    joined_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    left_at = Column(DateTime, nullable=True, index=True)

    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    location_updated_at = Column(DateTime, nullable=True, index=True)

    sos_active = Column(Boolean, default=False, nullable=False, index=True)
    sos_started_at = Column(DateTime, nullable=True)
    sos_escalated = Column(Boolean, default=False, nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("user_id", "event_id", name="uq_event_participant_user_event"),
        Index("ix_event_user_lookup", "event_id", "user_id"),
    )

    user = relationship("User", foreign_keys=[user_id], back_populates="event_participants")
    event = relationship("Event", foreign_keys=[event_id], back_populates="participants")
    group_members = relationship("GroupMember", foreign_keys="GroupMember.event_participant_id", back_populates="event_participant", cascade="all, delete-orphan")
