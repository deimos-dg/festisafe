import uuid as uuid_lib
import secrets
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from typing import List, Optional

from app.api.deps import get_current_user, require_roles
from app.db.session import get_db
from app.db.models.user import User
from app.db.models.event import Event
from app.db.models.event_participant import EventParticipant
from app.db.models.guest_code import GuestCode
from app.schemas.event import EventCreate, EventUpdate, EventResponse, EventParticipantResponse
from app.schemas.auth import GuestCodeResponse
from app.core.sanitizer import sanitize_name, sanitize_description, sanitize_location
from app.core.audit_log import log_security_event, AuditEvent

router = APIRouter(prefix="/events", tags=["Events"])


def _get_event_or_404(db: Session, event_id: str) -> Event:
    try:
        eid = uuid_lib.UUID(event_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Evento no encontrado")
    event = db.query(Event).filter(Event.id == eid).first()
    if not event:
        raise HTTPException(status_code=404, detail="Evento no encontrado")
    return event


@router.post("/", response_model=EventResponse, status_code=status.HTTP_201_CREATED)
def create_event(
    data: EventCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(["organizer", "admin"])),
):
    if data.ends_at <= data.starts_at:
        raise HTTPException(status_code=400, detail="ends_at debe ser posterior a starts_at")

    expires_at = data.expires_at or (data.ends_at + timedelta(days=7))
    if expires_at < data.ends_at:
        raise HTTPException(status_code=400, detail="expires_at debe ser posterior a ends_at")

    event = Event(
        name=sanitize_name(data.name),
        description=sanitize_description(data.description) if data.description else None,
        location_name=sanitize_location(data.location_name) if data.location_name else None,
        latitude=data.latitude,
        longitude=data.longitude,
        starts_at=data.starts_at,
        ends_at=data.ends_at,
        expires_at=expires_at,
        max_participants=data.max_participants,
        organizer_id=current_user.id,
        is_active=False,
    )
    db.add(event)
    db.flush()  # Obtener el ID del evento antes del commit

    # El organizador se une automáticamente como participante con rol 'organizer'
    participant = EventParticipant(
        event_id=event.id,
        user_id=current_user.id,
        role="organizer",
    )
    db.add(participant)
    db.commit()
    db.refresh(event)

    log_security_event(
        AuditEvent.EVENT_CREATED,
        user_id=str(current_user.id),
        detail=f"event_id={event.id} name={event.name}",
    )
    return event


@router.patch("/{event_id}", response_model=EventResponse)
def update_event(
    event_id: str,
    data: EventUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Edita un evento. Solo el organizador o admin."""
    event = _get_event_or_404(db, event_id)

    if event.organizer_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Sin permisos para editar este evento")

    # Calcular los valores finales para validar ANTES de mutar el objeto
    new_starts_at = data.starts_at if data.starts_at is not None else event.starts_at
    new_ends_at = data.ends_at if data.ends_at is not None else event.ends_at
    new_expires_at = data.expires_at if data.expires_at is not None else event.expires_at

    if new_ends_at <= new_starts_at:
        raise HTTPException(status_code=400, detail="ends_at debe ser posterior a starts_at")
    if new_expires_at < new_ends_at:
        raise HTTPException(status_code=400, detail="expires_at debe ser posterior a ends_at")

    if data.name is not None:
        event.name = data.name
    if data.description is not None:
        event.description = data.description
    if data.location_name is not None:
        event.location_name = data.location_name
    if data.latitude is not None:
        event.latitude = data.latitude
    if data.longitude is not None:
        event.longitude = data.longitude
    if data.starts_at is not None:
        event.starts_at = data.starts_at
    if data.ends_at is not None:
        event.ends_at = data.ends_at
    if data.expires_at is not None:
        event.expires_at = data.expires_at
    if data.max_participants is not None:
        event.max_participants = data.max_participants
    if data.meeting_point_lat is not None:
        event.meeting_point_lat = data.meeting_point_lat
    if data.meeting_point_lng is not None:
        event.meeting_point_lng = data.meeting_point_lng
    if data.meeting_point_name is not None:
        event.meeting_point_name = sanitize_name(data.meeting_point_name)

    db.commit()
    db.refresh(event)
    return event


@router.delete("/{event_id}", status_code=status.HTTP_200_OK)
def delete_event(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Elimina un evento. Solo el organizador o admin."""
    event = _get_event_or_404(db, event_id)

    if event.organizer_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Sin permisos para eliminar este evento")

    db.delete(event)
    db.commit()

    log_security_event(
        AuditEvent.EVENT_DELETED,
        user_id=str(current_user.id),
        detail=f"event_id={event_id}",
    )
    return {"message": "Evento eliminado correctamente"}


@router.post("/{event_id}/activate", response_model=EventResponse)
def activate_event(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _get_event_or_404(db, event_id)

    if event.organizer_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Sin permisos para activar este evento")
    if event.is_active:
        raise HTTPException(status_code=400, detail="El evento ya está activo")

    event.is_active = True
    db.commit()
    db.refresh(event)
    return event


@router.post("/{event_id}/deactivate", response_model=EventResponse)
def deactivate_event(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _get_event_or_404(db, event_id)

    if event.organizer_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Sin permisos para desactivar este evento")

    event.close_event()
    db.commit()
    db.refresh(event)
    return event


@router.get("/my", response_model=List[EventResponse])
def list_my_events(
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # JOIN directo — evita N+1 y aplica paginación correctamente
    return (
        db.query(Event)
        .join(EventParticipant, EventParticipant.event_id == Event.id)
        .filter(
            EventParticipant.user_id == current_user.id,
            EventParticipant.is_active == True,
        )
        .order_by(Event.starts_at.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )


@router.get("/search", response_model=List[EventResponse])
def search_events(
    q: Optional[str] = Query(None, max_length=100, description="Buscar por nombre o ubicación"),
    active_only: bool = Query(True),
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    query = db.query(Event)
    if active_only:
        query = query.filter(Event.is_active == True, Event.expires_at > datetime.utcnow())
    if q:
        # Sanitizar antes de usar en ilike para prevenir inyección de patrones LIKE
        safe_q = q.replace("%", r"\%").replace("_", r"\_")
        search = f"%{safe_q}%"
        query = query.filter(Event.name.ilike(search) | Event.location_name.ilike(search))
    return query.order_by(Event.starts_at.asc()).offset(skip).limit(limit).all()


@router.get("/public", response_model=List[EventResponse])
def search_events_public(
    q: Optional[str] = Query(None, max_length=100),
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
):
    """Búsqueda pública de eventos activos. No requiere autenticación."""
    query = db.query(Event).filter(Event.is_active == True, Event.expires_at > datetime.utcnow())
    if q:
        safe_q = q.replace("%", r"\%").replace("_", r"\_")
        search = f"%{safe_q}%"
        query = query.filter(Event.name.ilike(search) | Event.location_name.ilike(search))
    return query.order_by(Event.starts_at.asc()).offset(skip).limit(limit).all()


@router.get("/organized", response_model=List[EventResponse])
def list_organized_events(
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(["organizer", "admin"])),
):
    return db.query(Event).filter(
        Event.organizer_id == current_user.id
    ).offset(skip).limit(limit).all()


@router.get("/{event_id}", response_model=EventResponse)
def get_event(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_event_or_404(db, event_id)


@router.post("/{event_id}/join", status_code=status.HTTP_201_CREATED)
def join_event(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _get_event_or_404(db, event_id)

    if not event.is_active:
        raise HTTPException(status_code=403, detail="El evento no está activo")
    if event.expires_at < datetime.utcnow():
        raise HTTPException(status_code=403, detail="El evento ya expiró")

    existing = db.query(EventParticipant).filter(
        EventParticipant.event_id == event.id,
        EventParticipant.user_id == current_user.id,
    ).first()

    if existing:
        if existing.is_active:
            raise HTTPException(status_code=400, detail="Ya estás inscrito en este evento")
        # Reincorporación: verificar cupo antes de reactivar
        current_count = db.query(EventParticipant).filter(
            EventParticipant.event_id == event.id,
            EventParticipant.is_active == True,
        ).with_for_update().count()
        if current_count >= event.max_participants:
            raise HTTPException(status_code=403, detail="El evento está lleno")
        existing.is_active = True
        existing.left_at = None
        db.commit()
        return {"message": "Te reincorporaste al evento correctamente"}

    # Bloquear la fila del evento para evitar race condition en el conteo
    current_count = db.query(EventParticipant).filter(
        EventParticipant.event_id == event.id,
        EventParticipant.is_active == True,
    ).with_for_update().count()
    if current_count >= event.max_participants:
        raise HTTPException(status_code=403, detail="El evento está lleno")

    participant = EventParticipant(event_id=event.id, user_id=current_user.id)
    db.add(participant)
    db.commit()
    return {"message": "Te uniste al evento correctamente"}


@router.post("/{event_id}/leave", status_code=status.HTTP_200_OK)
def leave_event(
    event_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _get_event_or_404(db, event_id)

    participant = db.query(EventParticipant).filter(
        EventParticipant.event_id == event.id,
        EventParticipant.user_id == current_user.id,
        EventParticipant.is_active == True,
    ).first()

    if not participant:
        raise HTTPException(status_code=404, detail="No estás inscrito en este evento")

    participant.is_active = False
    participant.left_at = datetime.utcnow()
    db.commit()
    return {"message": "Saliste del evento correctamente"}


@router.get("/{event_id}/participants", response_model=List[EventParticipantResponse])
def list_participants(
    event_id: str,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _get_event_or_404(db, event_id)

    my_part = db.query(EventParticipant).filter(
        EventParticipant.event_id == event.id,
        EventParticipant.user_id == current_user.id,
        EventParticipant.is_active == True,
    ).first()

    if not my_part and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="No perteneces a este evento")

    rows = (
        db.query(EventParticipant, User)
        .join(User, EventParticipant.user_id == User.id)
        .filter(EventParticipant.event_id == event.id, EventParticipant.is_active == True)
        .offset(skip).limit(limit)
        .all()
    )

    return [
        EventParticipantResponse(
            id=ep.id,
            user_id=ep.user_id,
            event_id=ep.event_id,
            role=ep.role,
            is_active=ep.is_active,
            joined_at=ep.joined_at,
            name=u.name,
        )
        for ep, u in rows
    ]


# ---------------------------------------------------------
# Req 13: Generar código de invitado
# ---------------------------------------------------------

def _generate_unique_code(db: Session) -> str:
    """Genera un código numérico de 6 dígitos único usando secrets (CSPRNG)."""
    for _ in range(10):
        code = f"{secrets.randbelow(1_000_000):06d}"
        if not db.query(GuestCode).filter(GuestCode.code == code).first():
            return code
    raise HTTPException(status_code=500, detail="No se pudo generar un código único")


@router.post("/{event_id}/guest-code", response_model=GuestCodeResponse, status_code=status.HTTP_201_CREATED)
def generate_guest_code(
    event_id: str,
    expires_hours: int = Query(default=24, ge=1, le=168, description="Horas hasta expiración (máx. 7 días)"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(["organizer", "admin"])),
):
    """
    Genera un código OTP de 6 dígitos para una sola persona.
    max_uses está fijado en 1 — el código se invalida al primer uso.
    """
    event = _get_event_or_404(db, event_id)

    if event.organizer_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Sin permisos para generar códigos en este evento")

    code = _generate_unique_code(db)
    expires_at = datetime.utcnow() + timedelta(hours=expires_hours)

    guest_code = GuestCode(
        code=code,
        event_id=event.id,
        created_by=current_user.id,
        max_uses=1,          # OTP: siempre un solo uso
        expires_at=expires_at,
    )
    db.add(guest_code)
    db.commit()
    db.refresh(guest_code)

    return GuestCodeResponse(
        code=guest_code.code,
        expires_at=guest_code.expires_at.isoformat(),
        remaining_uses=guest_code.remaining_uses,
        event_id=str(event.id),
    )
