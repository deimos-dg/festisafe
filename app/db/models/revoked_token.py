from sqlalchemy import Column, Integer, String, DateTime
from sqlalchemy.sql import func

from app.db.base import Base


class RevokedToken(Base):
    __tablename__ = "revoked_tokens"

    id = Column(Integer, primary_key=True, index=True)
    jti = Column(String, unique=True, index=True, nullable=False)
    revoked_at = Column(DateTime(timezone=True), server_default=func.now())
