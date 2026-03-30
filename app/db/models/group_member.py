import uuid
from datetime import datetime

from sqlalchemy import Column, String, DateTime, Boolean, ForeignKey, UniqueConstraint, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class GroupMember(Base):
    __tablename__ = "group_members"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)

    group_id = Column(UUID(as_uuid=True), ForeignKey("groups.id", ondelete="CASCADE"), nullable=False, index=True)
    event_participant_id = Column(UUID(as_uuid=True), ForeignKey("event_participants.id", ondelete="CASCADE"), nullable=False, index=True)

    role = Column(String(30), default="member", nullable=False)
    is_active = Column(Boolean, default=True, nullable=False, index=True)

    joined_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    left_at = Column(DateTime, nullable=True, index=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("group_id", "event_participant_id", name="uq_group_member_unique"),
        Index("ix_group_member_lookup", "group_id", "event_participant_id"),
    )

    group = relationship("Group", foreign_keys=[group_id], back_populates="members")
    event_participant = relationship("EventParticipant", foreign_keys=[event_participant_id], back_populates="group_members")
