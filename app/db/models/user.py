import uuid
import enum
from datetime import datetime

from sqlalchemy import Column, String, Boolean, DateTime, Enum, Integer, Index, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class UserRole(str, enum.Enum):
    user = "user"
    organizer = "organizer"
    admin = "admin"
    company_admin = "company_admin"
    staff = "staff"


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)

    email = Column(String(255), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    name = Column(String(100), nullable=False, default="")
    phone = Column(String(30), nullable=True)

    role = Column(Enum(UserRole), default=UserRole.user, nullable=False, index=True)

    is_active = Column(Boolean, default=True, index=True)
    is_locked = Column(Boolean, default=False, index=True)

    failed_login_attempts = Column(Integer, default=0)
    lock_until = Column(DateTime, nullable=True, index=True)

    must_change_password = Column(Boolean, default=False)
    password_changed_at = Column(DateTime, default=datetime.utcnow)

    # Relación con Empresa
    company_id = Column(UUID(as_uuid=True), ForeignKey("companies.id", ondelete="SET NULL"), nullable=True, index=True)

    # Cuenta de invitado (creada automáticamente al canjear un Guest_Code)
    is_guest = Column(Boolean, default=False, index=True)

    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    event_participants = relationship("EventParticipant", foreign_keys="EventParticipant.user_id", back_populates="user", cascade="all, delete-orphan")
    organized_events = relationship("Event", foreign_keys="Event.organizer_id", back_populates="organizer")
    admin_groups = relationship("Group", foreign_keys="Group.admin_id", back_populates="admin")
    device_tokens = relationship("DeviceToken", back_populates="user", cascade="all, delete-orphan")
    password_reset_tokens = relationship("PasswordResetToken", back_populates="user", cascade="all, delete-orphan")
    company = relationship("Company", back_populates="users")
