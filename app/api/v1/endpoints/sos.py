import asyncio
import uuid as uuid_lib
from datetime import datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.db.models.user import User
from app.db.models.event import Event
from app.db.models.event_participant import EventParticipant
from app.db.models.group import Group
from app.db.models.group_member import GroupMember
from app.db.models.user_last_location import UserLastLocation
from app.db.models.device_token import DeviceToken
from app.schemas.sos import SOSActivateRequest, SOSStatusResponse
from app.core.ws_manager import manager
from app.core.audit_log import log_security_event, AuditEvent
from app.core.fcm import send_sos_push

router = APIRouter(prefix="/sos", tags=["SOS"])


def _parse_uuid(value: str, label: str = "ID"):
    try:
        return uuid_lib.UUID(value)
    except ValueError:
        raise HTTPException(status_code=404, detail=f"{label} inválido")


def _get_active_participant(db: Session, event_id, user_id) -> EventParticipant:
    p = db.query(EventParticipant).filter(
        EventParticipant.event_id == event_id,
        EventParticipant.user_id == user_id,
        EventParticipant.is_active == True,
    ).first()
    if not p:
        raise HTTPException(status_code=403, detail="No perteneces a este evento")
    return p


def _get_user_group(db: Session, participant_id) -> Group | None:
    gm = db.query(GroupMember).filter(
        GroupMember.event_participant_id == participant_id,
        GroupMember.is_active == True,
    ).first()
    return gm.group if gm else None


def _get_group_member_tokens(db: Session, event_id, group_id, exclude_user_id) -> list[str]:
    """Obtiene los tokens FCM de todos los miembros del grupo excepto el emisor."""
    rows = (
        db.query(DeviceToken.token)
        .join(EventParticipant, DeviceToken.user_id == EventParticipant.user_id)
        .join(GroupMember, GroupMember.event_participant_id == EventParticipant.id)
        .filter(
            EventParticipant.event_id == event_id,
            EventParticipant.is_active == True,
            GroupMember.group_id == group_id,
            GroupMember.is_active == True,
            DeviceToken.user_id != exclude_user_id,
        )
        .all()
    )
    return [r.token for r in rows]


def _get_organizer_tokens(db: Session, event_id) -> list[str]:
    """Obtiene los tokens FCM de los organizadores del evento."""
    rows = (
        db.query(DeviceToken.token)
        .join(EventParticipant, DeviceToken.user_id == EventParticipant.user_id)
        .filter(
            EventParticipant.event_id == event_id,
            EventParticipant.is_active == True,
            EventParticipant.role == "organizer",
        )
        .all()
    )
    return [r.token for r in rows]


@router.post("/{event_id}/activate", response_model=SOSStatusResponse)
async def activate_sos(
    event_id: str,
    data: SOSActivateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Activa la alerta SOS del usuario.
    Hace broadcast inmediato al grupo (incluido el emisor) y a los organizadores.
    """
    eid = _parse_uuid(event_id, "Evento")
    participant = _get_active_participant(db, eid, current_user.id)

    if participant.sos_active:
        raise HTTPException(status_code=400, detail="El SOS ya está activo")

    participant.sos_active = True
    participant.sos_started_at = datetime.utcnow()
    participant.sos_escalated = False

    # Actualizar/crear ubicación con la posición al momento del SOS (si viene)
    if data.latitude is not None and data.longitude is not None:
        location = db.query(UserLastLocation).filter(
            UserLastLocation.user_id == current_user.id,
            UserLastLocation.event_id == eid,
        ).first()

        if location:
            location.update_location(
                latitude=data.latitude,
                longitude=data.longitude,
                accuracy=data.accuracy,
            )
        else:
            location = UserLastLocation(
                user_id=current_user.id,
                event_id=eid,
                latitude=data.latitude,
                longitude=data.longitude,
                accuracy=data.accuracy,
            )
            db.add(location)
    else:
        # Sin coordenadas: usar la última ubicación conocida si existe
        location = db.query(UserLastLocation).filter(
            UserLastLocation.user_id == current_user.id,
            UserLastLocation.event_id == eid,
        ).first()

    db.commit()
    db.refresh(participant)

    group = _get_user_group(db, participant.id)
    group_id_str = str(group.id) if group else None

    log_security_event(
        AuditEvent.SOS_ACTIVATED,
        user_id=str(current_user.id),
        detail=f"event_id={event_id}",
    )

    alert = {
        "type": "sos",
        "user_id": str(current_user.id),
        "name": current_user.name,
        "event_id": event_id,
        "group_id": group_id_str,
        "latitude": data.latitude if data.latitude is not None else (location.latitude if location else None),
        "longitude": data.longitude if data.longitude is not None else (location.longitude if location else None),
        "accuracy": data.accuracy,
        "battery_level": data.battery_level,
        "triggered_at": participant.sos_started_at.isoformat(),
    }

    if group:
        # SOS llega a todo el grupo (sin excluir al emisor) + organizadores
        asyncio.create_task(
            manager.broadcast_sos(event_id, group_id_str, str(current_user.id), alert)
        )
    else:
        asyncio.create_task(manager.broadcast_to_organizers(event_id, alert))

    # --- NUEVO: Notificar al Portal Web de la Empresa ---
    if current_user.company_id:
        company_topic = f"company_{current_user.company_id}"
        asyncio.create_task(
            manager.broadcast_to_topic(company_topic, alert)
        )

    return participant


@router.post("/{event_id}/deactivate", response_model=SOSStatusResponse)
async def deactivate_sos(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Desactiva la alerta SOS y notifica al grupo y organizadores."""
    eid = _parse_uuid(event_id, "Evento")
    participant = _get_active_participant(db, eid, current_user.id)

    if not participant.sos_active:
        raise HTTPException(status_code=400, detail="No tienes un SOS activo")

    participant.sos_active = False
    participant.sos_started_at = None
    participant.sos_escalated = False
    db.commit()
    db.refresh(participant)

    group = _get_user_group(db, participant.id)
    group_id_str = str(group.id) if group else None

    cancel_alert = {
        "type": "sos_cancelled",
        "user_id": str(current_user.id),
        "name": current_user.name,
        "event_id": event_id,
        "group_id": group_id_str,
        "cancelled_at": datetime.utcnow().isoformat(),
    }

    if group:
        asyncio.create_task(
            manager.broadcast_sos(event_id, group_id_str, str(current_user.id), cancel_alert)
        )
    else:
        asyncio.create_task(manager.broadcast_to_organizers(event_id, cancel_alert))

    return participant


@router.post("/{event_id}/escalate/{target_user_id}", response_model=SOSStatusResponse)
async def escalate_sos(
    event_id: str,
    target_user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Escala el SOS de un usuario. Solo organizador del evento o admin."""
    eid = _parse_uuid(event_id, "Evento")
    uid = _parse_uuid(target_user_id, "Usuario")

    # Verificar que el usuario actual es organizador de ESTE evento o admin global
    if current_user.role != "admin":
        caller_participant = db.query(EventParticipant).filter(
            EventParticipant.event_id == eid,
            EventParticipant.user_id == current_user.id,
            EventParticipant.is_active == True,
            EventParticipant.role == "organizer",
        ).first()
        if not caller_participant:
            raise HTTPException(status_code=403, detail="Sin permisos para escalar SOS en este evento")

    participant = db.query(EventParticipant).filter(
        EventParticipant.event_id == eid,
        EventParticipant.user_id == uid,
        EventParticipant.is_active == True,
    ).first()

    if not participant:
        raise HTTPException(status_code=404, detail="Participante no encontrado")
    if not participant.sos_active:
        raise HTTPException(status_code=400, detail="El usuario no tiene SOS activo")

    participant.sos_escalated = True
    db.commit()
    db.refresh(participant)

    target_user = db.query(User).filter(User.id == uid).first()
    group = _get_user_group(db, participant.id)
    group_id_str = str(group.id) if group else None

    location = db.query(UserLastLocation).filter(
        UserLastLocation.user_id == uid,
        UserLastLocation.event_id == eid,
    ).first()

    escalate_alert = {
        "type": "sos_escalated",
        "user_id": target_user_id,
        "name": target_user.name if target_user else "Desconocido",
        "event_id": event_id,
        "group_id": group_id_str,
        "latitude": location.latitude if location else None,
        "longitude": location.longitude if location else None,
        "escalated_by": str(current_user.id),
        "escalated_at": datetime.utcnow().isoformat(),
    }

    if group:
        asyncio.create_task(
            manager.broadcast_sos(event_id, group_id_str, "", escalate_alert)
        )
    asyncio.create_task(manager.broadcast_to_organizers(event_id, escalate_alert))

    return participant


@router.get("/recent", response_model=List[dict])
def list_recent_sos(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Lista los SOS activos en todo el sistema para el dashboard de administración.
    Solo para administradores globales o de empresa.
    """
    query = db.query(EventParticipant, User).join(User, EventParticipant.user_id == User.id).filter(
        EventParticipant.sos_active == True
    )

    # Si es admin de empresa, solo ve los de su empresa
    if current_user.role != "admin" and current_user.company_id:
        query = query.filter(User.company_id == current_user.company_id)
    elif current_user.role != "admin":
        raise HTTPException(status_code=403, detail="No tienes permisos para ver todas las alertas")

    rows = query.all()
    results = []
    for p, u in rows:
        # Buscar la última ubicación
        loc = db.query(UserLastLocation).filter(
            UserLastLocation.user_id == u.id,
            UserLastLocation.event_id == p.event_id
        ).first()

        results.append({
            "id": str(p.id),
            "user_id": str(u.id),
            "name": u.name or "Usuario",
            "event_id": str(p.event_id),
            "latitude": loc.latitude if loc else None,
            "longitude": loc.longitude if loc else None,
            "started_at": p.sos_started_at.isoformat() if p.sos_started_at else None,
            "status": "warning" if p.sos_active else "stable"
        })
    return results

@router.get("/{event_id}/active", response_model=List[SOSStatusResponse])
def list_active_sos(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Lista todos los SOS activos en el evento. Solo miembros del evento."""
    eid = _parse_uuid(event_id, "Evento")
    _get_active_participant(db, eid, current_user.id)

    return db.query(EventParticipant).filter(
        EventParticipant.event_id == eid,
        EventParticipant.sos_active == True,
    ).all()
