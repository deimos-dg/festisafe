import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey, UniqueConstraint, Enum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
import enum
from app.db.base import Base


class JoinRequestStatus(str, enum.Enum):
    pending = "pending"
    accepted = "accepted"
    rejected = "rejected"


class GroupJoinRequest(Base):
    """Solicitud de un participante para unirse a un grupo."""
    __tablename__ = "group_join_requests"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    group_id = Column(UUID(as_uuid=True), ForeignKey("groups.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    status = Column(Enum(JoinRequestStatus), default=JoinRequestStatus.pending, nullable=False, index=True)
    message = Column(String(200), nullable=True)  # mensaje opcional del solicitante
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    group = relationship("Group", back_populates="join_requests")
    user = relationship("User")

    __table_args__ = (
        # Un usuario solo puede tener una solicitud pendiente por grupo
        UniqueConstraint("group_id", "user_id", name="uq_group_join_request"),
    )
