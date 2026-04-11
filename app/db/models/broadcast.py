import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey, Enum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
import enum
from app.db.base import Base

class BroadcastTarget(str, enum.Enum):
    all = "all"
    security = "security"
    medical = "medical"
    staff = "staff"

class BroadcastMessage(Base):
    __tablename__ = "broadcast_messages"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    company_id = Column(UUID(as_uuid=True), ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    sender_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    title = Column(String(100), nullable=False)
    content = Column(String(500), nullable=False)

    # Filtrado por puesto
    target_role = Column(Enum(BroadcastTarget), default=BroadcastTarget.all)

    created_at = Column(DateTime, default=datetime.utcnow)

    company = relationship("Company")
    sender = relationship("User")
