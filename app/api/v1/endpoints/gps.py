import uuid as uuid_lib
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.api.deps import get_current_user
from app.schemas.location import LocationCreate, LocationOut
from app.db.models.user_last_location import UserLastLocation
from app.db.models.event_participant import EventParticipant
from app.db.models.group_member import GroupMember
from app.db.models.user import User

router = APIRouter(prefix="/gps", tags=["GPS"])


def _parse_uuid(value: str, label: str = "ID"):
    try:
        return uuid_lib.UUID(value)
    except ValueError:
        raise HTTPException(status_code=404, detail=f"{label} inválido")


def _get_active_participant(db: Session, event_id, user_id):
    p = db.query(EventParticipant).filter(
        EventParticipant.event_id == event_id,
        EventParticipant.user_id == user_id,
        EventParticipant.is_active == True,
    ).first()
    if not p:
        raise HTTPException(status_code=403, detail="No perteneces a este evento")
    return p


@router.post("/location/{event_id}", response_model=LocationOut)
def update_location(
    event_id: str,
    data: LocationCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Actualiza o crea la última ubicación del usuario en un evento (fallback HTTP)."""
    eid = _parse_uuid(event_id, "Evento")
    _get_active_participant(db, eid, current_user.id)

    location = db.query(UserLastLocation).filter(
        UserLastLocation.user_id == current_user.id,
        UserLastLocation.event_id == eid,
    ).first()

    if location:
        location.update_location(latitude=data.latitude, longitude=data.longitude, accuracy=data.accuracy)
    else:
        location = UserLastLocation(
            user_id=current_user.id,
            event_id=eid,
            latitude=data.latitude,
            longitude=data.longitude,
            accuracy=data.accuracy,
        )
        db.add(location)

    db.commit()
    db.refresh(location)

    result = LocationOut.model_validate(location)
    result.name = current_user.name or ""
    return result


@router.get("/location/{event_id}", response_model=list[LocationOut])
def get_event_locations(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Devuelve las últimas ubicaciones visibles de los participantes del evento.
    - Organizadores/admin: ven a todos los participantes del evento.
    - Usuarios normales: solo ven a los miembros de su propio grupo.
    """
    eid = _parse_uuid(event_id, "Evento")
    my_participant = _get_active_participant(db, eid, current_user.id)

    is_organizer = current_user.role in ("organizer", "admin")

    if is_organizer:
        # Organizadores ven todas las ubicaciones del evento
        rows = (
            db.query(UserLastLocation, User)
            .join(User, UserLastLocation.user_id == User.id)
            .filter(
                UserLastLocation.event_id == eid,
                UserLastLocation.is_visible == True,
            )
            .all()
        )
    else:
        # Usuarios normales: solo su grupo
        my_gm = db.query(GroupMember).filter(
            GroupMember.event_participant_id == my_participant.id,
            GroupMember.is_active == True,
        ).first()

        if not my_gm:
            # Sin grupo — solo devuelve su propia ubicación
            rows = (
                db.query(UserLastLocation, User)
                .join(User, UserLastLocation.user_id == User.id)
                .filter(
                    UserLastLocation.event_id == eid,
                    UserLastLocation.user_id == current_user.id,
                )
                .all()
            )
        else:
            # Obtener user_ids de los miembros activos del grupo
            group_participant_ids = db.query(GroupMember.event_participant_id).filter(
                GroupMember.group_id == my_gm.group_id,
                GroupMember.is_active == True,
            ).subquery()

            group_user_ids = db.query(EventParticipant.user_id).filter(
                EventParticipant.id.in_(group_participant_ids),
            ).subquery()

            rows = (
                db.query(UserLastLocation, User)
                .join(User, UserLastLocation.user_id == User.id)
                .filter(
                    UserLastLocation.event_id == eid,
                    UserLastLocation.is_visible == True,
                    UserLastLocation.user_id.in_(group_user_ids),
                )
                .all()
            )

    results = []
    for loc, user in rows:
        out = LocationOut.model_validate(loc)
        out.name = user.name or ""
        results.append(out)
    return results


@router.patch("/visibility/{event_id}", response_model=LocationOut)
def toggle_visibility(
    event_id: str,
    visible: bool,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Activa o desactiva la visibilidad del usuario en el mapa."""
    eid = _parse_uuid(event_id, "Evento")
    _get_active_participant(db, eid, current_user.id)

    location = db.query(UserLastLocation).filter(
        UserLastLocation.user_id == current_user.id,
        UserLastLocation.event_id == eid,
    ).first()

    if not location:
        raise HTTPException(status_code=404, detail="No tienes ubicación registrada en este evento")

    location.is_visible = visible
    db.commit()
    db.refresh(location)

    result = LocationOut.model_validate(location)
    result.name = current_user.name or ""
    return result
