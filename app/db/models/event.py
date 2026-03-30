import uuid
from datetime import datetime

from sqlalchemy import Column, String, DateTime, Boolean, ForeignKey, Integer, Float, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class Event(Base):
    __tablename__ = "events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)

    name = Column(String(255), nullable=False)
    description = Column(String(500), nullable=True)
    location_name = Column(String(255), nullable=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)

    starts_at = Column(DateTime, nullable=False, index=True)
    ends_at = Column(DateTime, nullable=False, index=True)
    expires_at = Column(DateTime, nullable=False, index=True)

    is_active = Column(Boolean, default=True, index=True)

    organizer_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    max_participants = Column(Integer, default=8)

    # Punto de encuentro — coordenadas y nombre opcional
    meeting_point_lat = Column(Float, nullable=True)
    meeting_point_lng = Column(Float, nullable=True)
    meeting_point_name = Column(String(255), nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    organizer = relationship("User", foreign_keys=[organizer_id], back_populates="organized_events")
    participants = relationship("EventParticipant", foreign_keys="EventParticipant.event_id", back_populates="event", cascade="all, delete-orphan")
    groups = relationship("Group", foreign_keys="Group.event_id", back_populates="event", cascade="all, delete-orphan")

    __table_args__ = (
        Index("ix_event_active_window", "is_active", "starts_at", "expires_at"),
        Index("ix_event_organizer_active", "organizer_id", "is_active"),
    )

    def is_event_active(self) -> bool:
        now = datetime.utcnow()
        return self.is_active and self.starts_at <= now <= self.expires_at

    def close_event(self):
        self.is_active = False
