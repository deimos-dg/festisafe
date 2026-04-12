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


def _haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6_371_000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _point_in_polygon(lat: float, lon: float, polygon: list) -> bool:
    """Ray-casting: True si el punto está dentro del polígono."""
    n = len(polygon)
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = polygon[i][0], polygon[i][1]
        xj, yj = polygon[j][0], polygon[j][1]
        if ((yi > lon) != (yj > lon)) and (lat < (xj - xi) * (lon - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside


def _is_inside_geofence(geofence: Geofence, lat: float, lon: float) -> bool:
    if geofence.radius_meters and geofence.latitude and geofence.longitude:
        return _haversine_meters(lat, lon, geofence.latitude, geofence.longitude) <= geofence.radius_meters
    if geofence.polygon_points and len(geofence.polygon_points) >= 3:
        return _point_in_polygon(lat, lon, geofence.polygon_points)
    return False


def check_geofences():
    """
    Evalúa cada 2 minutos si algún empleado entró o salió de una geofence activa.
    Solo procesa ubicaciones actualizadas en los últimos 5 minutos.
    """
    db: Session = SessionLocal()
    try:
        import asyncio
        from app.core.ws_manager import manager

        now = datetime.utcnow()
        stale_cutoff = now - timedelta(minutes=5)

        geofences = db.query(Geofence).filter(Geofence.is_active == True).all()
        if not geofences:
            return

        company_geofences: dict = {}
        for gf in geofences:
            company_geofences.setdefault(str(gf.company_id), []).append(gf)

        for company_id_str, gf_list in company_geofences.items():
            rows = (
                db.query(UserLastLocation, User)
                .join(User, UserLastLocation.user_id == User.id)
                .filter(
                    User.company_id == gf_list[0].company_id,
                    UserLastLocation.updated_at >= stale_cutoff,
                    UserLastLocation.is_visible == True,
                )
                .all()
            )

            for loc, user in rows:
                for gf in gf_list:
                    currently_inside = _is_inside_geofence(gf, loc.latitude, loc.longitude)

                    last_event = (
                        db.query(GeofenceEvent)
                        .filter(
                            GeofenceEvent.geofence_id == gf.id,
                            GeofenceEvent.user_id == user.id,
                        )
                        .order_by(GeofenceEvent.created_at.desc())
                        .first()
                    )

                    was_inside = last_event.is_inside if last_event else False
                    if currently_inside == was_inside:
                        continue

                    event_type = "entered" if currently_inside else "exited"
                    db.add(GeofenceEvent(
                        geofence_id=gf.id,
                        user_id=user.id,
                        event_type=event_type,
                        is_inside=currently_inside,
                    ))

                    alert = {
                        "type": "geofence_alert",
                        "event_type": event_type,
                        "geofence_id": str(gf.id),
                        "geofence_name": gf.name,
                        "geofence_type": gf.type,
                        "user_id": str(user.id),
                        "user_name": user.name,
                        "latitude": loc.latitude,
                        "longitude": loc.longitude,
                        "timestamp": now.isoformat(),
                    }
                    topic = f"company_{company_id_str}"
                    try:
                        loop = asyncio.get_event_loop()
                        if loop.is_running():
                            asyncio.ensure_future(manager.broadcast_to_topic(topic, alert))
                        else:
                            loop.run_until_complete(manager.broadcast_to_topic(topic, alert))
                    except RuntimeError:
                        asyncio.run(manager.broadcast_to_topic(topic, alert))

                    logger.info(f"Geofence: {user.name} {event_type} '{gf.name}'")

        db.commit()

    except Exception as e:
        logger.error(f"Scheduler check_geofences error: {e}")
        db.rollback()
    finally:
        db.close()


def deactivate_expired_events():
    """Desactiva eventos cuyo expires_at ya pasó."""
    db: Session = SessionLocal()
    try:
        now = datetime.utcnow()
        expired = db.query(Event).filter(
            Event.is_active == True,
            Event.expires_at <= now,
        ).all()
        count = len(expired)
        for event in expired:
            event.is_active = False
        if count:
            db.commit()
            logger.info(f"Scheduler: desactivados {count} eventos expirados")
    except Exception as e:
        logger.error(f"Scheduler deactivate_expired_events error: {e}")
        db.rollback()
    finally:
        db.close()


def purge_location_history():
    """Elimina puntos del historial de ubicaciones con más de 30 días."""
    db: Session = SessionLocal()
    try:
        from app.db.models.user_location_history import UserLocationHistory
        cutoff = datetime.utcnow() - timedelta(days=30)
        deleted = db.query(UserLocationHistory).filter(
            UserLocationHistory.created_at < cutoff
        ).delete(synchronize_session=False)
        if deleted:
            db.commit()
            logger.info(f"Scheduler: eliminados {deleted} puntos de historial de ubicación")
    except Exception as e:
        logger.error(f"Scheduler purge_location_history error: {e}")
        db.rollback()
    finally:
        db.close()


def notify_expiring_contracts():    """
    Detecta empresas cuyo contrato vence en los próximos 7 días
    y envía una alerta WS al portal para que el admin lo vea.
    Se ejecuta una vez al día.
    """
    db: Session = SessionLocal()
    try:
        import asyncio
        from app.core.ws_manager import manager
        from app.db.models.company import Company, CompanyStatus

        now = datetime.utcnow()
        warning_cutoff = now + timedelta(days=7)

        expiring = db.query(Company).filter(
            Company.status == CompanyStatus.active,
            Company.contract_end != None,
            Company.contract_end > now,
            Company.contract_end <= warning_cutoff,
        ).all()

        for company in expiring:
            days_left = (company.contract_end - now).days
            alert = {
                "type": "contract_expiring",
                "company_id": str(company.id),
                "company_name": company.name,
                "days_left": days_left,
                "contract_end": company.contract_end.isoformat(),
            }
            # Notificar al super admin via broadcast general
            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    asyncio.ensure_future(manager.broadcast_to_topic("super_admin", alert))
                else:
                    loop.run_until_complete(manager.broadcast_to_topic("super_admin", alert))
            except RuntimeError:
                asyncio.run(manager.broadcast_to_topic("super_admin", alert))

            logger.info(f"Scheduler: contrato de '{company.name}' vence en {days_left} días")

    except Exception as e:
        logger.error(f"Scheduler notify_expiring_contracts error: {e}")
    finally:
        db.close()


def start_scheduler():
    scheduler.add_job(check_geofences, "interval", minutes=2, id="check_geofences")
    scheduler.add_job(deactivate_expired_events, "interval", minutes=5, id="deactivate_events")
    scheduler.add_job(cleanup_expired_groups, "interval", minutes=30, id="cleanup_groups")
    scheduler.add_job(cleanup_revoked_tokens, "interval", hours=1, id="cleanup_tokens")
    scheduler.add_job(cleanup_expired_reset_tokens, "interval", hours=24, id="cleanup_reset_tokens")
    scheduler.add_job(notify_expiring_contracts, "interval", hours=24, id="notify_expiring", jitter=3600)
    scheduler.add_job(purge_location_history, "interval", days=7, id="purge_history")
    scheduler.start()
    logger.info("Scheduler iniciado")
