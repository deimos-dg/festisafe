import uuid as uuid_lib
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from app.api.deps import get_current_user
from app.db.session import get_db
from app.db.models.user import User
from app.db.models.group import Group
from app.db.models.group_member import GroupMember
from app.db.models.event_participant import EventParticipant
from app.db.models.event import Event

router = APIRouter(prefix="/group-members", tags=["Group Members"])


def _parse_uuid(value: str, label: str = "ID"):
    try:
        return uuid_lib.UUID(value)
    except ValueError:
        raise HTTPException(status_code=404, detail=f"{label} inválido")


@router.post("/add/{group_id}", status_code=status.HTTP_201_CREATED)
def add_member(
    group_id: str,
    user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    gid = _parse_uuid(group_id, "Grupo")
    uid = _parse_uuid(user_id, "Usuario")

    group = db.query(Group).filter(Group.id == gid).first()
    if not group:
        raise HTTPException(status_code=404, detail="Grupo no encontrado")

    if group.admin_id != current_user.id:
        raise HTTPException(status_code=403, detail="Solo el admin puede agregar miembros")

    event = db.query(Event).filter(Event.id == group.event_id).first()
    if not event or not event.is_active:
        raise HTTPException(status_code=403, detail="El evento no está activo")

    if group.is_closed:
        raise HTTPException(status_code=403, detail="El grupo está cerrado")

    participant = db.query(EventParticipant).filter(
        EventParticipant.event_id == group.event_id,
        EventParticipant.user_id == uid,
        EventParticipant.is_active == True,
    ).first()
    if not participant:
        raise HTTPException(status_code=403, detail="El usuario no pertenece al evento")

    # SELECT FOR UPDATE — bloqueo a nivel fila para prevenir race condition
    # Dos requests simultáneos no pueden superar max_members
    db.query(Group).filter(Group.id == gid).with_for_update().first()

    current_count = db.query(GroupMember).filter(
        GroupMember.group_id == gid,
        GroupMember.is_active == True,
    ).count()
    if current_count >= group.max_members:
        raise HTTPException(status_code=403, detail="El grupo está lleno")

    existing = db.query(GroupMember).filter(
        GroupMember.group_id == gid,
        GroupMember.event_participant_id == participant.id,
    ).first()
    if existing:
        if existing.is_active:
            raise HTTPException(status_code=400, detail="El usuario ya está en el grupo")
        # Reactivar si salió antes
        existing.is_active = True
        existing.left_at = None
        db.commit()
        return {"message": "Miembro reincorporado correctamente"}

    try:
        member = GroupMember(group_id=gid, event_participant_id=participant.id)
        db.add(member)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="Error de integridad en base de datos")

    return {"message": "Miembro agregado correctamente"}


@router.delete("/remove/{group_id}/{user_id}", status_code=status.HTTP_200_OK)
def remove_member(
    group_id: str,
    user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    gid = _parse_uuid(group_id, "Grupo")
    uid = _parse_uuid(user_id, "Usuario")

    group = db.query(Group).filter(Group.id == gid).first()
    if not group:
        raise HTTPException(status_code=404, detail="Grupo no encontrado")

    is_admin = group.admin_id == current_user.id
    is_self = uid == current_user.id

    if not is_admin and not is_self:
        raise HTTPException(status_code=403, detail="Sin permisos para eliminar este miembro")

    # No se puede expulsar al admin
    if is_admin and uid == current_user.id:
        raise HTTPException(status_code=400, detail="El admin no puede expulsarse a sí mismo. Usa /leave")

    participant = db.query(EventParticipant).filter(
        EventParticipant.event_id == group.event_id,
        EventParticipant.user_id == uid,
    ).first()
    if not participant:
        raise HTTPException(status_code=404, detail="Participante no encontrado")

    member = db.query(GroupMember).filter(
        GroupMember.group_id == gid,
        GroupMember.event_participant_id == participant.id,
        GroupMember.is_active == True,
    ).first()
    if not member:
        raise HTTPException(status_code=404, detail="El usuario no está en el grupo")

    member.is_active = False
    member.left_at = datetime.utcnow()
    db.commit()

    return {"message": "Miembro eliminado correctamente"}
