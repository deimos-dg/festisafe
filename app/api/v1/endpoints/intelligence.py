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
    name: str,
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
    company_id: Optional[UUID] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Envía un mensaje masivo a los empleados.
    - Super admin: puede especificar company_id o dejar vacío para broadcast global.
    - Company admin: solo puede enviar a su propia empresa.
    """
    # Determinar la empresa destino
    if current_user.role == UserRole.admin:
        # Super admin puede enviar a una empresa específica o a todas
        target_company_id = company_id
    elif current_user.company_id:
        target_company_id = current_user.company_id
    else:
        raise HTTPException(status_code=403, detail="No tienes empresa asignada")

    msg = BroadcastMessage(
        company_id=target_company_id,
        sender_id=current_user.id,
        title=title,
        content=content,
        target_role=target,
    )
    db.add(msg)
    db.commit()

    if target_company_id:
        # Broadcast a empresa específica
        topic = f"company_{target_company_id}"
        await manager.broadcast_to_topic(topic, {
            "type": "broadcast",
            "title": title,
            "content": content,
            "sender": current_user.name,
        })
    else:
        # Super admin broadcast global — enviar a todos los tópicos activos
        alert = {"type": "broadcast", "title": title, "content": content, "sender": current_user.name}
        companies = db.query(User.company_id).filter(
            User.company_id != None
        ).distinct().all()
        for (cid,) in companies:
            await manager.broadcast_to_topic(f"company_{cid}", alert)

    return {"status": "sent", "id": str(msg.id)}

@router.get("/heatmap")
def get_heatmap_data(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Retorna puntos de calor basados en la ubicación actual de los empleados"""
    from app.api.v1.endpoints.companies import check_is_company_admin
    from app.db.models.user_last_location import UserLastLocation

    # Solo admins de empresa o admin global pueden ver el heatmap
    if not current_user.company_id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="No tienes permisos para ver este recurso")

    if current_user.company_id:
        check_is_company_admin(current_user, current_user.company_id)

    company_filter = (
        db.query(User.id).filter(User.company_id == current_user.company_id)
        if current_user.company_id
        else db.query(User.id)  # admin global ve todos
    )

    points = db.query(UserLastLocation.latitude, UserLastLocation.longitude).filter(
        UserLastLocation.user_id.in_(company_filter)
    ).all()

    return [{"lat": p.latitude, "lng": p.longitude, "intensity": 1.0} for p in points]
