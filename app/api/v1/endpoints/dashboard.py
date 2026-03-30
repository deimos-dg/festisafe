from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.db.session import get_db
from app.db.models.user import User
from app.db.models.event import Event
from app.db.models.event_participant import EventParticipant
from app.db.models.group import Group
from app.db.models.group_member import GroupMember

router = APIRouter(tags=["Dashboard"])


@router.get("/dashboard")
def dashboard(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Resumen del usuario autenticado:
    - Eventos en los que participa
    - Grupos activos
    - SOS activos en sus eventos
    """
    # Eventos activos del usuario
    my_events = (
        db.query(Event)
        .join(EventParticipant, EventParticipant.event_id == Event.id)
        .filter(
            EventParticipant.user_id == current_user.id,
            EventParticipant.is_active == True,
            Event.is_active == True,
        )
        .all()
    )

    # Grupos del usuario
    my_groups = (
        db.query(Group)
        .join(GroupMember, GroupMember.group_id == Group.id)
        .join(EventParticipant, GroupMember.event_participant_id == EventParticipant.id)
        .filter(
            EventParticipant.user_id == current_user.id,
            GroupMember.is_active == True,
        )
        .all()
    )

    # SOS activos en los eventos del usuario (subquery SQL, no lista Python)
    my_event_ids_sq = (
        db.query(EventParticipant.event_id)
        .filter(
            EventParticipant.user_id == current_user.id,
            EventParticipant.is_active == True,
        )
        .subquery()
    )

    active_sos = (
        db.query(EventParticipant)
        .filter(
            EventParticipant.event_id.in_(my_event_ids_sq),
            EventParticipant.sos_active == True,
        )
        .count()
    )

    return {
        "user": {
            "id": str(current_user.id),
            "name": current_user.name,
            "role": current_user.role,
        },
        "active_events": len(my_events),
        "active_groups": len(my_groups),
        "active_sos_in_my_events": active_sos,
        "events": [
            {
                "id": str(e.id),
                "name": e.name,
                "location_name": e.location_name,
                "starts_at": e.starts_at.isoformat(),
                "ends_at": e.ends_at.isoformat(),
            }
            for e in my_events
        ],
    }
