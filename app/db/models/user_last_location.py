import uuid
from datetime import datetime

from sqlalchemy import Column, DateTime, Float, Boolean, ForeignKey, UniqueConstraint, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class UserLastLocation(Base):
    __tablename__ = "user_last_locations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)

    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id", ondelete="CASCADE"), nullable=False, index=True)

    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    accuracy = Column(Float, nullable=True)
    speed = Column(Float, nullable=True)
    heading = Column(Float, nullable=True)

    is_visible = Column(Boolean, default=True, nullable=False, index=True)

    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False, index=True)

    __table_args__ = (
        UniqueConstraint("user_id", "event_id", name="uq_user_event_last_location"),
        Index("ix_location_event_lookup", "event_id", "updated_at"),
        Index("ix_location_user_lookup", "user_id", "event_id"),
    )

    user = relationship("User", foreign_keys=[user_id])
    event = relationship("Event", foreign_keys=[event_id])

    def update_location(self, latitude: float, longitude: float, accuracy: float | None = None,
                        speed: float | None = None, heading: float | None = None):
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.speed = speed
        self.heading = heading
        self.updated_at = datetime.utcnow()

    def hide(self): self.is_visible = False
    def show(self): self.is_visible = True
