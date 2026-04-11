from typing import List, Optional
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.api.deps import get_current_user
from app.db.models.user import User, UserRole
from app.db.models.geofence import Geofence, GeofenceType
from app.db.models.broadcast import BroadcastMessage, BroadcastTarget
from app.db.models.user_location_history import UserLocationHistory
from app.core.ws_manager import manager

router = APIRouter(prefix="/intelligence", tags=["Intelligence"])

@router.post("/geofences")
def create_geofence(
    name: String,
    type: GeofenceType,
    polygon_points: Optional[List[List[float]]] = None,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    radius: Optional[float] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Crea una zona de control (Geocerca)"""
    if not current_user.company_id:
        raise HTTPException(status_code=400, detail="Acceso denegado")

    new_geo = Geofence(
        company_id=current_user.company_id,
        name=name,
        type=type,
        polygon_points=polygon_points,
        latitude=latitude,
        longitude=longitude,
        radius_meters=radius
    )
    db.add(new_geo)
    db.commit()
    return new_geo

@router.post("/broadcast")
async def send_broadcast(
    title: str,
    content: str,
    target: BroadcastTarget,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Envía un mensaje masivo a los empleados de la empresa"""
    if not current_user.company_id:
        raise HTTPException(status_code=403)

    msg = BroadcastMessage(
        company_id=current_user.company_id,
        sender_id=current_user.id,
        title=title,
        content=content,
        target_role=target
    )
    db.add(msg)
    db.commit()

    # Broadcast vía WebSocket a todos los conectados de la empresa
    topic = f"company_{current_user.company_id}"
    alert = {
        "type": "broadcast",
        "title": title,
        "content": content,
        "sender": current_user.name
    }
    await manager.broadcast_to_topic(topic, alert)

    return {"status": "sent", "id": str(msg.id)}

@router.get("/heatmap")
def get_heatmap_data(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Retorna puntos de calor basados en la ubicación actual de los empleados"""
    from app.db.models.user_last_location import UserLastLocation

    points = db.query(UserLastLocation.latitude, UserLastLocation.longitude).filter(
        UserLastLocation.user_id.in_(
            db.query(User.id).filter(User.company_id == current_user.company_id)
        )
    ).all()

    return [{"lat": p.latitude, "lng": p.longitude, "intensity": 1.0} for p in points]
