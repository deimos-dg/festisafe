import uuid as uuid_lib
import asyncio
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime

from app.api.deps import get_current_user
from app.db.session import get_db
from app.db.models.user import User
from app.db.models.group import Group
from app.db.models.group_member import GroupMember
from app.db.models.event_participant import EventParticipant
from app.db.models.group_join_request import GroupJoinRequest, JoinRequestStatus
from app.schemas.group import GroupCreate, GroupResponse
from app.db.models.event import Event
from app.core.ws_manager import manager
from app.core.sanitizer import sanitize_name

router = APIRouter(prefix="/groups", tags=["Groups"])


def _parse_uuid(value: str, label: str = "ID"):
    try:
        return uuid_lib.UUID(value)
    except ValueError:
        raise HTTPException(status_code=404, detail=f"{label} inválido")


def _get_group_or_404(db: Session, group_id: str) -> Group:
    gid = _parse_uuid(group_id, "Grupo")
    g = db.query(Group).filter(Group.id == gid).first()
    if not g:
        raise HTTPException(status_code=404, detail="Grupo no encontrado")
    return g


def _get_participant_or_403(db: Session, event_id, user_id) -> EventParticipant:
    p = db.query(EventParticipant).filter(
        EventParticipant.event_id == event_id,
        EventParticipant.user_id == user_id,
        EventParticipant.is_active == True,
    ).first()
    if not p:
        raise HTTPException(status_code=403, detail="No perteneces a este evento")
    return p


@router.post("/", status_code=status.HTTP_201_CREATED)
def create_group(
    data: GroupCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    eid = _parse_uuid(data.event_id, "Evento")
    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        raise HTTPException(status_code=404, detail="Evento no encontrado")
    if not event.is_active:
        raise HTTPException(status_code=403, detail="El evento no está activo")

    participant = _get_participant_or_403(db, eid, current_user.id)

    existing = db.query(Group).filter(
        Group.event_id == eid,
        Group.admin_id == current_user.id,
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Ya tienes un grupo en este evento")

    group = Group(name=data.name, event_id=eid, admin_id=current_user.id)
    db.add(group)
    db.commit()
    db.refresh(group)

    member = GroupMember(group_id=group.id, event_participant_id=participant.id)
    db.add(member)
    db.commit()

    return {"message": "Grupo creado correctamente", "group_id": str(group.id)}


@router.get("/my/{event_id}")
def get_my_group(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    eid = _parse_uuid(event_id, "Evento")
    participant = _get_participant_or_403(db, eid, current_user.id)

    gm = db.query(GroupMember).filter(
        GroupMember.event_participant_id == participant.id,
        GroupMember.is_active == True,
    ).first()

    if not gm:
        raise HTTPException(status_code=404, detail="No perteneces a ningún grupo en este evento")

    group = gm.group
    return {
        "group_id": str(group.id),
        "name": group.name,
        "admin_id": str(group.admin_id),
        "is_closed": group.is_closed,
        "max_members": group.max_members,
        "meeting_point_lat": group.meeting_point_lat,
        "meeting_point_lng": group.meeting_point_lng,
        "meeting_point_name": group.meeting_point_name,
    }


@router.get("/{group_id}")
def get_group(
    group_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Detalle de un grupo por ID."""
    group = _get_group_or_404(db, group_id)

    # Verificar que el usuario pertenece al evento del grupo (o es admin)
    if current_user.role != "admin":
        _get_participant_or_403(db, group.event_id, current_user.id)

    return {
        "group_id": str(group.id),
        "name": group.name,
        "event_id": str(group.event_id),
        "admin_id": str(group.admin_id),
        "is_closed": group.is_closed,
        "max_members": group.max_members,
        "created_at": group.created_at,
        "meeting_point_lat": group.meeting_point_lat,
        "meeting_point_lng": group.meeting_point_lng,
        "meeting_point_name": group.meeting_point_name,
    }


@router.get("/{group_id}/members")
def list_group_members(
    group_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    group = _get_group_or_404(db, group_id)

    # Verificar que el usuario pertenece al evento
    my_participant = db.query(EventParticipant).filter(
        EventParticipant.event_id == group.event_id,
        EventParticipant.user_id == current_user.id,
        EventParticipant.is_active == True,
    ).first()

    if not my_participant and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="No perteneces a este evento")

    # Es privilegiado si es admin global o es organizador de ESTE evento
    is_privileged = current_user.role == "admin" or (
        my_participant and my_participant.role == "organizer"
    )

    if not is_privileged:
        is_member = db.query(GroupMember).filter(
            GroupMember.group_id == group.id,
            GroupMember.event_participant_id == my_participant.id,
            GroupMember.is_active == True,
        ).first()
        if not is_member:
            raise HTTPException(status_code=403, detail="No perteneces a este grupo")

    rows = (
        db.query(GroupMember, EventParticipant, User)
        .join(EventParticipant, GroupMember.event_participant_id == EventParticipant.id)
        .join(User, EventParticipant.user_id == User.id)
        .filter(GroupMember.group_id == group.id, GroupMember.is_active == True)
        .all()
    )

    return {
        "group_id": str(group.id),
        "name": group.name,
        "total_members": len(rows),
        "members": [
            {
                "user_id": str(u.id),
                "name": u.name,
                "role": gm.role,
                "joined_at": gm.joined_at,
            }
            for gm, ep, u in rows
        ],
    }


@router.post("/{group_id}/transfer-admin")
def transfer_admin(
    group_id: str,
    new_admin_user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    group = _get_group_or_404(db, group_id)

    if group.admin_id != current_user.id:
        raise HTTPException(status_code=403, detail="Solo el admin puede transferir la administración")

    new_uid = _parse_uuid(new_admin_user_id, "Usuario")

    new_participant = db.query(EventParticipant).filter(
        EventParticipant.event_id == group.event_id,
        EventParticipant.user_id == new_uid,
        EventParticipant.is_active == True,
    ).first()
    if not new_participant:
        raise HTTPException(status_code=404, detail="El usuario no pertenece al evento")

    new_member = db.query(GroupMember).filter(
        GroupMember.group_id == group.id,
        GroupMember.event_participant_id == new_participant.id,
        GroupMember.is_active == True,
    ).first()
    if not new_member:
        raise HTTPException(status_code=404, detail="El usuario no es miembro del grupo")

    # Bajar rol del admin actual
    current_participant = db.query(EventParticipant).filter(
        EventParticipant.event_id == group.event_id,
        EventParticipant.user_id == current_user.id,
    ).first()
    if current_participant:
        old_member = db.query(GroupMember).filter(
            GroupMember.group_id == group.id,
            GroupMember.event_participant_id == current_participant.id,
        ).first()
        if old_member:
            old_member.role = "member"

    new_member.role = "admin"
    group.admin_id = new_uid
    db.commit()

    return {"message": "Administración transferida correctamente"}


@router.post("/{group_id}/leave")
def leave_group(
    group_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    group = _get_group_or_404(db, group_id)

    participant = db.query(EventParticipant).filter(
        EventParticipant.event_id == group.event_id,
        EventParticipant.user_id == current_user.id,
    ).first()
    if not participant:
        raise HTTPException(status_code=404, detail="No perteneces al evento de este grupo")

    member = db.query(GroupMember).filter(
        GroupMember.group_id == group.id,
        GroupMember.event_participant_id == participant.id,
        GroupMember.is_active == True,
    ).first()
    if not member:
        raise HTTPException(status_code=404, detail="No eres miembro de este grupo")

    is_admin = group.admin_id == current_user.id

    # Contar miembros restantes EXCLUYENDO al que sale
    remaining = db.query(GroupMember).filter(
        GroupMember.group_id == group.id,
        GroupMember.is_active == True,
        GroupMember.id != member.id,
    ).count()

    if is_admin and remaining > 0:
        raise HTTPException(status_code=400, detail="Transfiere la administración antes de salir del grupo")

    member.is_active = False
    member.left_at = datetime.utcnow()

    if remaining == 0:
        db.delete(group)

    db.commit()
    return {"message": "Saliste del grupo correctamente"}


@router.delete("/{group_id}", status_code=status.HTTP_200_OK)
def delete_group(
    group_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    group = _get_group_or_404(db, group_id)

    if group.admin_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Solo el administrador puede eliminar el grupo")

    db.delete(group)
    db.commit()
    return {"message": "Grupo eliminado correctamente"}


# ---------------------------------------------------------------------------
# Punto de encuentro del grupo
# ---------------------------------------------------------------------------

@router.patch("/{group_id}/meeting-point", status_code=status.HTTP_200_OK)
async def set_group_meeting_point(
    group_id: str,
    lat: float,
    lng: float,
    name: str = "",
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Establece o actualiza el punto de encuentro del grupo.
    Solo el admin del grupo puede hacerlo.
    Notifica a todos los miembros vía WebSocket con tipo 'group_meeting_point'.
    """
    group = _get_group_or_404(db, group_id)

    if group.admin_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Solo el admin del grupo puede establecer el punto de encuentro")

    if not (-90 <= lat <= 90):
        raise HTTPException(status_code=400, detail="Latitud inválida")
    if not (-180 <= lng <= 180):
        raise HTTPException(status_code=400, detail="Longitud inválida")

    group.meeting_point_lat = lat
    group.meeting_point_lng = lng
    group.meeting_point_name = sanitize_name(name) if name.strip() else None
    group.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(group)

    # Notificar a todos los miembros del grupo vía WS
    event_id_str = str(group.event_id)
    asyncio.create_task(
        manager._send_to_channel(
            event_id_str,
            group_id,
            {
                "type": "group_meeting_point",
                "group_id": group_id,
                "group_name": group.name,
                "lat": lat,
                "lng": lng,
                "name": group.meeting_point_name or "",
                "updated_by": current_user.name,
            },
        )
    )

    return {
        "message": "Punto de encuentro actualizado",
        "group_id": group_id,
        "meeting_point_lat": lat,
        "meeting_point_lng": lng,
        "meeting_point_name": group.meeting_point_name,
    }


@router.delete("/{group_id}/meeting-point", status_code=status.HTTP_200_OK)
def clear_group_meeting_point(
    group_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Elimina el punto de encuentro del grupo. Solo el admin."""
    group = _get_group_or_404(db, group_id)

    if group.admin_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Solo el admin del grupo puede eliminar el punto de encuentro")

    group.meeting_point_lat = None
    group.meeting_point_lng = None
    group.meeting_point_name = None
    group.updated_at = datetime.utcnow()
    db.commit()

    return {"message": "Punto de encuentro eliminado"}


# ---------------------------------------------------------------------------
# Solicitudes de unión al grupo
# ---------------------------------------------------------------------------

@router.get("/event/{event_id}/available")
def list_available_groups(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Lista los grupos disponibles (no cerrados, con cupo) en un evento.
    Incluye el conteo de miembros actuales y si el usuario ya tiene solicitud pendiente.
    """
    eid = _parse_uuid(event_id, "Evento")
    _get_participant_or_403(db, eid, current_user.id)

    groups = db.query(Group).filter(
        Group.event_id == eid,
        Group.is_closed == False,
    ).all()

    result = []
    for g in groups:
        member_count = db.query(GroupMember).filter(
            GroupMember.group_id == g.id,
            GroupMember.is_active == True,
        ).count()

        # Verificar si el usuario ya es miembro
        my_participant = db.query(EventParticipant).filter(
            EventParticipant.event_id == eid,
            EventParticipant.user_id == current_user.id,
            EventParticipant.is_active == True,
        ).first()
        is_member = False
        if my_participant:
            is_member = db.query(GroupMember).filter(
                GroupMember.group_id == g.id,
                GroupMember.event_participant_id == my_participant.id,
                GroupMember.is_active == True,
            ).first() is not None

        # Verificar si ya tiene solicitud pendiente
        pending_request = db.query(GroupJoinRequest).filter(
            GroupJoinRequest.group_id == g.id,
            GroupJoinRequest.user_id == current_user.id,
            GroupJoinRequest.status == JoinRequestStatus.pending,
        ).first()

        result.append({
            "group_id": str(g.id),
            "name": g.name,
            "member_count": member_count,
            "max_members": g.max_members,
            "is_full": member_count >= g.max_members,
            "is_member": is_member,
            "has_pending_request": pending_request is not None,
        })

    return result


@router.post("/{group_id}/request-join", status_code=status.HTTP_201_CREATED)
async def request_join_group(
    group_id: str,
    message: str = "",
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Envía una solicitud para unirse al grupo.
    Notifica al admin del grupo vía WebSocket con tipo 'group_join_request'.
    """
    group = _get_group_or_404(db, group_id)
    event_id_str = str(group.event_id)

    # Verificar que el usuario pertenece al evento
    participant = _get_participant_or_403(db, group.event_id, current_user.id)

    if group.is_closed:
        raise HTTPException(status_code=403, detail="El grupo está cerrado")

    # Verificar cupo
    member_count = db.query(GroupMember).filter(
        GroupMember.group_id == group.id,
        GroupMember.is_active == True,
    ).count()
    if member_count >= group.max_members:
        raise HTTPException(status_code=403, detail="El grupo está lleno")

    # Verificar que no sea ya miembro
    is_member = db.query(GroupMember).filter(
        GroupMember.group_id == group.id,
        GroupMember.event_participant_id == participant.id,
        GroupMember.is_active == True,
    ).first()
    if is_member:
        raise HTTPException(status_code=400, detail="Ya eres miembro de este grupo")

    # Verificar solicitud duplicada
    existing = db.query(GroupJoinRequest).filter(
        GroupJoinRequest.group_id == group.id,
        GroupJoinRequest.user_id == current_user.id,
    ).first()
    if existing:
        if existing.status == JoinRequestStatus.pending:
            raise HTTPException(status_code=400, detail="Ya tienes una solicitud pendiente para este grupo")
        # Reutilizar si fue rechazada antes
        existing.status = JoinRequestStatus.pending
        existing.message = message[:200] if message else None
        existing.updated_at = datetime.utcnow()
        db.commit()
        req_id = str(existing.id)
    else:
        req = GroupJoinRequest(
            group_id=group.id,
            user_id=current_user.id,
            message=message[:200] if message else None,
        )
        db.add(req)
        db.commit()
        db.refresh(req)
        req_id = str(req.id)

    # Notificar al admin del grupo vía WS si está conectado
    admin_id_str = str(group.admin_id)
    asyncio.create_task(
        manager._send_to_channel(
            event_id_str,
            "__organizers__",  # admins de grupo también escuchan aquí si son organizadores
            {
                "type": "group_join_request",
                "request_id": req_id,
                "group_id": group_id,
                "group_name": group.name,
                "user_id": str(current_user.id),
                "user_name": current_user.name,
                "message": message[:200] if message else "",
            },
        )
    )
    # También enviar directamente al canal del grupo si el admin está ahí
    asyncio.create_task(
        manager._send_to_channel(
            event_id_str,
            group_id,
            {
                "type": "group_join_request",
                "request_id": req_id,
                "group_id": group_id,
                "group_name": group.name,
                "user_id": str(current_user.id),
                "user_name": current_user.name,
                "message": message[:200] if message else "",
            },
            exclude=str(current_user.id),
        )
    )

    return {"message": "Solicitud enviada correctamente", "request_id": req_id}


@router.get("/{group_id}/requests")
def list_join_requests(
    group_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Lista las solicitudes pendientes del grupo. Solo el admin puede verlas."""
    group = _get_group_or_404(db, group_id)

    if group.admin_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Solo el admin del grupo puede ver las solicitudes")

    rows = (
        db.query(GroupJoinRequest, User)
        .join(User, GroupJoinRequest.user_id == User.id)
        .filter(
            GroupJoinRequest.group_id == group.id,
            GroupJoinRequest.status == JoinRequestStatus.pending,
        )
        .all()
    )

    return [
        {
            "request_id": str(req.id),
            "user_id": str(u.id),
            "user_name": u.name,
            "message": req.message,
            "created_at": req.created_at,
        }
        for req, u in rows
    ]


@router.post("/{group_id}/requests/{request_id}/accept", status_code=status.HTTP_200_OK)
async def accept_join_request(
    group_id: str,
    request_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Acepta una solicitud de unión. Solo el admin del grupo."""
    group = _get_group_or_404(db, group_id)

    if group.admin_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Solo el admin puede aceptar solicitudes")

    rid = _parse_uuid(request_id, "Solicitud")
    req = db.query(GroupJoinRequest).filter(
        GroupJoinRequest.id == rid,
        GroupJoinRequest.group_id == group.id,
        GroupJoinRequest.status == JoinRequestStatus.pending,
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada o ya procesada")

    # Verificar cupo antes de aceptar (con lock para evitar race condition)
    member_count = db.query(GroupMember).filter(
        GroupMember.group_id == group.id,
        GroupMember.is_active == True,
    ).with_for_update().count()
    if member_count >= group.max_members:
        raise HTTPException(status_code=403, detail="El grupo está lleno")

    # Obtener el participant del solicitante
    participant = db.query(EventParticipant).filter(
        EventParticipant.event_id == group.event_id,
        EventParticipant.user_id == req.user_id,
        EventParticipant.is_active == True,
    ).first()
    if not participant:
        req.status = JoinRequestStatus.rejected
        db.commit()
        raise HTTPException(status_code=404, detail="El usuario ya no pertenece al evento")

    # Agregar como miembro
    existing_member = db.query(GroupMember).filter(
        GroupMember.group_id == group.id,
        GroupMember.event_participant_id == participant.id,
    ).first()
    if existing_member:
        existing_member.is_active = True
        existing_member.left_at = None
    else:
        db.add(GroupMember(group_id=group.id, event_participant_id=participant.id))

    req.status = JoinRequestStatus.accepted
    req.updated_at = datetime.utcnow()
    db.commit()

    # Notificar al solicitante vía WS
    event_id_str = str(group.event_id)
    user_id_str = str(req.user_id)
    asyncio.create_task(
        manager._send_to_channel(
            event_id_str,
            group_id,
            {
                "type": "group_join_accepted",
                "group_id": group_id,
                "group_name": group.name,
                "user_id": user_id_str,
            },
        )
    )

    return {"message": "Solicitud aceptada. El usuario fue agregado al grupo."}


@router.post("/{group_id}/requests/{request_id}/reject", status_code=status.HTTP_200_OK)
async def reject_join_request(
    group_id: str,
    request_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Rechaza una solicitud de unión. Solo el admin del grupo."""
    group = _get_group_or_404(db, group_id)

    if group.admin_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Solo el admin puede rechazar solicitudes")

    rid = _parse_uuid(request_id, "Solicitud")
    req = db.query(GroupJoinRequest).filter(
        GroupJoinRequest.id == rid,
        GroupJoinRequest.group_id == group.id,
        GroupJoinRequest.status == JoinRequestStatus.pending,
    ).first()
    if not req:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada o ya procesada")

    req.status = JoinRequestStatus.rejected
    req.updated_at = datetime.utcnow()
    db.commit()

    # Notificar al solicitante
    event_id_str = str(group.event_id)
    asyncio.create_task(
        manager._send_to_channel(
            event_id_str,
            group_id,
            {
                "type": "group_join_rejected",
                "group_id": group_id,
                "group_name": group.name,
                "user_id": str(req.user_id),
            },
        )
    )

    return {"message": "Solicitud rechazada."}
