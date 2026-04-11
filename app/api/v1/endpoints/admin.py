from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import List, Optional
from datetime import datetime

from app.api.deps import require_roles
from app.db.session import get_db
from app.db.models.user import User, UserRole
from app.db.models.event import Event
from app.db.models.event_participant import EventParticipant
from app.schemas.user import UserResponse
from app.core.limiter import limiter

router = APIRouter(prefix="/admin", tags=["Admin"])


@router.get("/users", response_model=List[UserResponse])
@limiter.limit("30/minute")
def list_users(
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    role: Optional[UserRole] = None,
    is_active: Optional[bool] = None,
    q: Optional[str] = Query(None, max_length=100, description="Buscar por nombre o email"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(["admin"])),
):
    """Lista todos los usuarios con filtros opcionales."""
    query = db.query(User)
    if role:
        query = query.filter(User.role == role)
    if is_active is not None:
        query = query.filter(User.is_active == is_active)
    if q:
        safe_q = q.replace("%", r"\%").replace("_", r"\_")
        search = f"%{safe_q}%"
        query = query.filter(User.name.ilike(search) | User.email.ilike(search))
    return query.order_by(User.created_at.desc()).offset(skip).limit(limit).all()


@router.patch("/users/{user_id}/activate", response_model=UserResponse)
def activate_user(
    user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(["admin"])),
):
    """Activa una cuenta de usuario."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    user.is_active = True
    user.is_locked = False
    user.lock_until = None
    db.commit()
    db.refresh(user)
    return user


@router.patch("/users/{user_id}/deactivate", response_model=UserResponse)
def deactivate_user(
    user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(["admin"])),
):
    """Desactiva una cuenta de usuario."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    if str(user.id) == str(current_user.id):
        raise HTTPException(status_code=400, detail="No puedes desactivar tu propia cuenta")
    user.is_active = False
    db.commit()
    db.refresh(user)
    return user


@router.patch("/users/{user_id}/unlock", response_model=UserResponse)
def unlock_user(
    user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(["admin"])),
):
    """Desbloquea manualmente una cuenta bloqueada por fuerza bruta."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    user.is_locked = False
    user.lock_until = None
    user.failed_login_attempts = 0
    user.must_change_password = False
    db.commit()
    db.refresh(user)
    return user


@router.get("/events", response_model=List[dict])
def list_all_events(
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    is_active: Optional[bool] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(["admin"])),
):
    """Lista todos los eventos del sistema."""
    # Subquery para contar participantes activos por evento en una sola query
    participant_count_sq = (
        db.query(
            EventParticipant.event_id,
            func.count(EventParticipant.id).label("count"),
        )
        .filter(EventParticipant.is_active == True)
        .group_by(EventParticipant.event_id)
        .subquery()
    )

    query = db.query(Event, func.coalesce(participant_count_sq.c.count, 0).label("participant_count")).outerjoin(
        participant_count_sq, Event.id == participant_count_sq.c.event_id
    )
    if is_active is not None:
        query = query.filter(Event.is_active == is_active)

    rows = query.order_by(Event.created_at.desc()).offset(skip).limit(limit).all()

    return [
        {
            "id": str(e.id),
            "name": e.name,
            "is_active": e.is_active,
            "starts_at": e.starts_at.isoformat(),
            "ends_at": e.ends_at.isoformat(),
            "organizer_id": str(e.organizer_id) if e.organizer_id else None,
            "participant_count": count,
        }
        for e, count in rows
    ]


@router.get("/stats")
def get_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(["admin"])),
):
    """Estadísticas generales del sistema."""
    from app.db.models.company import Company
    return {
        "total_users": db.query(User).count(),
        "total_companies": db.query(Company).count(),
        "active_users": db.query(User).filter(User.is_active == True).count(),
        "locked_users": db.query(User).filter(User.is_locked == True).count(),
        "total_events": db.query(Event).count(),
        "active_events": db.query(Event).filter(Event.is_active == True).count(),
        "active_sos": db.query(EventParticipant).filter(EventParticipant.sos_active == True).count(),
    }

# Endpoint seed-test-data eliminado — era una vulnerabilidad crítica (sin autenticación)
