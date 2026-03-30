from datetime import datetime

from sqlalchemy import Column, Integer, String, Boolean, DateTime, Index

from app.db.base import Base


class LoginAttempt(Base):
    __tablename__ = "login_attempts"

    id = Column(Integer, primary_key=True, index=True)

    email = Column(String(255), nullable=False, index=True)
    ip_address = Column(String(45), nullable=True)  # Soporta IPv6
    success = Column(Boolean, default=False, nullable=False)

    timestamp = Column(DateTime, default=datetime.utcnow, index=True)

    __table_args__ = (
        Index("ix_login_attempt_email_timestamp", "email", "timestamp"),
    )

    def __repr__(self):
        return f"<LoginAttempt email={self.email} success={self.success}>"