import uuid
from datetime import datetime
from sqlalchemy import Column, String, Float, DateTime, ForeignKey, Enum, JSON, Boolean, event as sa_event
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

    def validate_polygon(self) -> bool:
        """Valida que el polígono tenga al menos 3 puntos y coordenadas válidas."""
        if self.polygon_points is None:
            return True  # Geofence circular — no aplica
        if not isinstance(self.polygon_points, list):
            return False
        if len(self.polygon_points) < 3:
            return False
        for point in self.polygon_points:
            if not isinstance(point, (list, tuple)) or len(point) != 2:
                return False
            lat, lng = point
            if not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
                return False
        return True


@sa_event.listens_for(Geofence, "before_insert")
@sa_event.listens_for(Geofence, "before_update")
def validate_geofence(mapper, connection, target):
    if not target.validate_polygon():
        raise ValueError(
            "polygon_points inválido: debe tener al menos 3 puntos con coordenadas válidas"
        )
