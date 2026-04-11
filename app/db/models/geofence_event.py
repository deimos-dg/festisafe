"""
Registro de eventos de geofence: entrada y salida de zonas de control.
Permite detectar transiciones sin disparar alertas duplicadas.
"""
import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, ForeignKey, Boolean
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from app.db.base import Base


class GeofenceEvent(Base):
    __tablename__ = "geofence_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    geofence_id = Column(
        UUID(as_uuid=True),
        ForeignKey("geofences.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # "entered" | "exited"
    event_type = Column(String(10), nullable=False)

    # true mientras el usuario sigue dentro de la zona
    is_inside = Column(Boolean, default=True, nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    geofence = relationship("Geofence")
    user = relationship("User")
