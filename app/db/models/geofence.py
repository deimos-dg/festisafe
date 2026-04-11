import uuid
from datetime import datetime
from sqlalchemy import Column, String, Float, DateTime, ForeignKey, Enum, JSON, Boolean
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
import enum
import uuid
from datetime import datetime
from app.db.base import Base

class GeofenceType(str, enum.Enum):
    safe_zone = "safe_zone"
    danger_zone = "danger_zone"
    restricted = "restricted"

class Geofence(Base):
    __tablename__ = "geofences"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    company_id = Column(UUID(as_uuid=True), ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)

    name = Column(String(100), nullable=False)
    type = Column(Enum(GeofenceType), default=GeofenceType.safe_zone)

    # Coordenadas: Central (para circulares) o Lista de puntos (para polígonos)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    radius_meters = Column(Float, nullable=True)

    # Para polígonos complejos: [[lat, lng], [lat, lng], ...]
    polygon_points = Column(JSON, nullable=True)

    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    company = relationship("Company")
