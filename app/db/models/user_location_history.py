import uuid
from datetime import datetime
from sqlalchemy import Column, DateTime, Float, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID
from app.db.base import Base

class UserLocationHistory(Base):
    """
    Almacena el rastro histórico de ubicaciones para reconstruir trayectorias.
    Se recomienda purgar estos datos periódicamente (ej: cada 30 días).
    """
    __tablename__ = "user_location_history"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    # Opcional: Vincular a un evento si el punto ocurrió dentro de uno
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id", ondelete="SET NULL"), nullable=True, index=True)

    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    accuracy = Column(Float, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    # Índices para búsquedas rápidas por tiempo y usuario
    __table_args__ = (
        Index("ix_history_user_time", "user_id", "created_at"),
    )
