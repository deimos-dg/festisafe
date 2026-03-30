import uuid
from datetime import datetime

from sqlalchemy import Column, String, ForeignKey, Boolean, Integer, DateTime, Float, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class Group(Base):
    __tablename__ = "groups"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    name = Column(String(255), nullable=False)

    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id", ondelete="CASCADE"), nullable=False, index=True)
    admin_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    is_closed = Column(Boolean, default=False, index=True)
    max_members = Column(Integer, default=8)

    # Punto de encuentro propio del grupo
    meeting_point_lat = Column(Float, nullable=True)
    meeting_point_lng = Column(Float, nullable=True)
    meeting_point_name = Column(String(255), nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    event = relationship("Event", foreign_keys=[event_id], back_populates="groups")
    admin = relationship("User", foreign_keys=[admin_id], back_populates="admin_groups")
    members = relationship("GroupMember", foreign_keys="GroupMember.group_id", back_populates="group", cascade="all, delete-orphan")
    join_requests = relationship("GroupJoinRequest", back_populates="group", cascade="all, delete-orphan")

    __table_args__ = (
        Index("ix_group_event_admin", "event_id", "admin_id"),
    )
