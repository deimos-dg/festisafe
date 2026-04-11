import logging
from apscheduler.schedulers.background import BackgroundScheduler
from datetime import datetime, timedelta
import math
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.db.models.event import Event
from app.db.models.group import Group
from app.db.models.revoked_token import RevokedToken
from app.db.models.geofence import Geofence, GeofenceType
from app.db.models.geofence_event import GeofenceEvent
from app.db.models.user_last_location import UserLastLocation
from app.db.models.user import User
from app.crud import password_reset_token as crud_password_reset_token

logger = logging.getLogger(__name__)
scheduler = BackgroundScheduler()


def cleanup_expired_groups():
    """Elimina grupos de eventos que terminaron hace más de 12 horas."""
    db: Session = SessionLocal()
    try:
        now = datetime.utcnow()
        expired_events = db.query(Event).filter(
            Event.ends_at + timedelta(hours=12) < now
        ).all()

        count = 0
        for event in expired_events:
            groups = db.query(Group).filter(Group.event_id == event.id).all()
            for group in groups:
                db.delete(group)  # cascade elimina GroupMember automáticamente
                count += 1

        if count:
            db.commit()
            logger.info(f"Scheduler: eliminados {count} grupos expirados")

    except Exception as e:
        logger.error(f"Scheduler cleanup_expired_groups error: {e}")
        db.rollback()
    finally:
        db.close()


def cleanup_revoked_tokens():
    """Elimina tokens revocados cuya fecha de revocación supera el TTL máximo de un refresh token."""
    db: Session = SessionLocal()
    try:
        from app.core.config import settings
        from datetime import timedelta

        # Un token revocado ya no tiene utilidad una vez que su TTL máximo expiró.
        # El refresh token tiene el TTL más largo, así que usamos ese como referencia.
        cutoff = datetime.utcnow() - timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

        deleted = db.query(RevokedToken).filter(
            RevokedToken.revoked_at < cutoff
        ).delete(synchronize_session=False)

        if deleted:
            db.commit()
            logger.info(f"Scheduler: eliminados {deleted} tokens revocados expirados")

    except Exception as e:
        logger.error(f"Scheduler cleanup_revoked_tokens error: {e}")
        db.rollback()
    finally:
        db.close()


def cleanup_expired_reset_tokens():
    """Elimina tokens de recuperación de contraseña expirados hace más de 24 horas."""
    db: Session = SessionLocal()
    try:
        deleted = crud_password_reset_token.cleanup_expired_tokens(db)
        if deleted:
            logger.info(f"Scheduler: eliminados {deleted} tokens de recuperación expirados")
    except Exception as e:
        logger.error(f"Scheduler cleanup_expired_reset_tokens error: {e}")
        db.rollback()
    finally:
        db.close()


def start_scheduler():
    scheduler.add_job(check_geofences, "interval", minutes=2, id="check_geofences")
    scheduler.add_job(deactivate_expired_events, "interval", minutes=5, id="deactivate_events")
    scheduler.add_job(cleanup_expired_groups, "interval", minutes=30, id="cleanup_groups")
    scheduler.add_job(cleanup_revoked_tokens, "interval", hours=1, id="cleanup_tokens")
    scheduler.add_job(cleanup_expired_reset_tokens, "interval", hours=24, id="cleanup_reset_tokens")
    scheduler.start()
    logger.info("Scheduler iniciado")
