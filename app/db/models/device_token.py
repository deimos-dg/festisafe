import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from app.db.base import Base


class DeviceToken(Base):
    """Token FCM por dispositivo. Un usuario puede tener varios dispositivos."""
    __tablename__ = "device_tokens"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    token = Column(String(512), nullable=False)
    platform = Column(String(10), nullable=False, default="android")  # android | ios
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user = relationship("User", back_populates="device_tokens")

    __table_args__ = (
        # Un token es único globalmente (un dispositivo no puede pertenecer a dos usuarios)
        UniqueConstraint("token", name="uq_device_token"),
    )
