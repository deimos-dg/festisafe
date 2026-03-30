import json
import asyncio
import uuid as uuid_lib
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from sqlalchemy.orm import Session

from app.core.ws_manager import manager
from app.core.security import decode_token
from app.db.session import SessionLocal
from app.db.models.user import User
from app.db.models.event import Event
from app.db.models.event_participant import EventParticipant
from app.db.models.group import Group
from app.db.models.group_member import GroupMember
from app.db.models.user_last_location import UserLastLocation

router = APIRouter(tags=["WebSocket"])

HEARTBEAT_INTERVAL = 30  # segundos entre pings del servidor

# Límite de conexiones WebSocket simultáneas por usuario
_WS_MAX_CONNECTIONS_PER_USER = 3
# Registro de conexiones activas: user_id -> count
_ws_active_connections: dict[str, int] = {}


def _ws_acquire(user_id: str) -> bool:
    """Registra una nueva conexión WS. Retorna False si se supera el límite."""
    count = _ws_active_connections.get(user_id, 0)
    if count >= _WS_MAX_CONNECTIONS_PER_USER:
        return False
    _ws_active_connections[user_id] = count + 1
    return True


def _ws_release(user_id: str) -> None:
    """Libera una conexión WS al desconectarse."""
    count = _ws_active_connections.get(user_id, 0)
    if count <= 1:
        _ws_active_connections.pop(user_id, None)
    else:
        _ws_active_connections[user_id] = count - 1


def _get_db() -> Session:
    return SessionLocal()


def _parse_uuid(value: str):
    try:
        return uuid_lib.UUID(value)
    except (ValueError, AttributeError):
        return None


def _authenticate(token: str, db: Session) -> User | None:
    try:
        payload = decode_token(token)
    except Exception:
        return None
    if payload.get("type") != "access":
        return None
    user_id = payload.get("sub")
    if not user_id:
        return None
    uid = _parse_uuid(user_id)
    if not uid:
        return None
    user = db.query(User).filter(User.id == uid).first()
    if not user or not user.is_active or user.is_locked:
        return None
    return user


def _get_group_for_user(db: Session, event_id, user_id) -> Group | None:
    participant = db.query(EventParticipant).filter(
        EventParticipant.event_id == event_id,
        EventParticipant.user_id == user_id,
        EventParticipant.is_active == True,
    ).first()
    if not participant:
        return None
    gm = db.query(GroupMember).filter(
        GroupMember.event_participant_id == participant.id,
        GroupMember.is_active == True,
    ).first()
    return gm.group if gm else None


def _upsert_location(db: Session, user_id, event_id, lat: float, lon: float, accuracy: float | None):
    loc = db.query(UserLastLocation).filter(
        UserLastLocation.user_id == user_id,
        UserLastLocation.event_id == event_id,
    ).first()
    if loc:
        loc.update_location(latitude=lat, longitude=lon, accuracy=accuracy)
    else:
        loc = UserLastLocation(user_id=user_id, event_id=event_id, latitude=lat, longitude=lon, accuracy=accuracy)
        db.add(loc)
    db.commit()


@router.websocket("/ws/location/{event_id}")
async def ws_location(
    websocket: WebSocket,
    event_id: str,
):
    """
    WebSocket de ubicación en tiempo real.

    El cliente debe enviar como primer mensaje:
      {"type": "auth", "token": "<JWT access token>"}

    Mensajes entrantes (JSON):
      - Ubicación:  {"type": "location", "latitude": float, "longitude": float, "accuracy": float|null}
      - Pong:       {"type": "pong"}

    Mensajes salientes:
      - Confirmación: {"type": "connected", "group_id": str|null, "role": str}
      - Ubicación:    {"type": "location", "user_id": str, ...}
      - Ping:         {"type": "ping"}
      - Error:        {"type": "error", "detail": str}
    """
    db = _get_db()
    try:
        # 1. Aceptar la conexión para poder recibir el primer mensaje de auth
        await websocket.accept()

        # 2. Esperar el mensaje de autenticación con timeout
        try:
            raw_auth = await asyncio.wait_for(websocket.receive_text(), timeout=10.0)
            auth_data = json.loads(raw_auth)
        except (asyncio.TimeoutError, ValueError, TypeError):
            await websocket.send_json({"type": "error", "detail": "Se esperaba mensaje de autenticación"})
            await websocket.close(code=4001, reason="Auth timeout")
            return

        if auth_data.get("type") != "auth" or not auth_data.get("token"):
            await websocket.send_json({"type": "error", "detail": "Primer mensaje debe ser {type: auth, token: ...}"})
            await websocket.close(code=4001, reason="Token requerido")
            return

        # 3. Autenticar
        user = _authenticate(auth_data["token"], db)
        if not user:
            await websocket.send_json({"type": "error", "detail": "Token inválido"})
            await websocket.close(code=4001, reason="Token inválido")
            return

        # 4. Parsear y validar event_id
        eid = _parse_uuid(event_id)
        if not eid:
            await websocket.close(code=4003, reason="ID de evento inválido")
            return

        # 5. Validar evento activo — renumerado desde el refactor de auth
        event = db.query(Event).filter(Event.id == eid).first()
        if not event or not event.is_active:
            await websocket.close(code=4003, reason="Evento no activo")
            return

        # 5. Validar pertenencia al evento
        participant = db.query(EventParticipant).filter(
            EventParticipant.event_id == eid,
            EventParticipant.user_id == user.id,
            EventParticipant.is_active == True,
        ).first()
        if not participant:
            await websocket.close(code=4003, reason="No perteneces a este evento")
            return

        # 6. Límite de conexiones simultáneas por usuario (anti-DoS WS)
        user_id_str = str(user.id)
        if not _ws_acquire(user_id_str):
            await websocket.close(code=4008, reason="Demasiadas conexiones simultáneas")
            return

        # 7. Grupo o canal de organizador
        group = _get_group_for_user(db, eid, user.id)
        is_organizer = user.role in ("organizer", "admin")

        if not group and not is_organizer:
            await websocket.close(code=4003, reason="No perteneces a ningún grupo en este evento")
            return

        group_id_str = str(group.id) if group else None
        channel = group_id_str  # valor por defecto

        # Conectar al canal de organizadores siempre que sea organizador/admin
        if is_organizer:
            manager.connect_organizer(event_id, user_id_str, websocket)
            channel = "__organizers__"

        # Si además tiene grupo, conectar también al canal del grupo
        if group_id_str:
            manager.connect(event_id, group_id_str, user_id_str, websocket)
            if not is_organizer:
                channel = group_id_str

        await websocket.send_json({
            "type": "connected",
            "group_id": group_id_str,
            "role": user.role,
        })

        # Heartbeat: ping cada HEARTBEAT_INTERVAL segundos
        async def heartbeat():
            while True:
                await asyncio.sleep(HEARTBEAT_INTERVAL)
                try:
                    await websocket.send_json({"type": "ping"})
                except Exception:
                    break

        heartbeat_task = asyncio.create_task(heartbeat())

        try:
            while True:
                raw = await websocket.receive_text()

                try:
                    data = json.loads(raw)
                except (ValueError, TypeError):
                    await websocket.send_json({"type": "error", "detail": "JSON inválido"})
                    continue

                msg_type = data.get("type")

                if msg_type == "pong":
                    continue

                if msg_type == "location":
                    try:
                        lat = float(data["latitude"])
                        lon = float(data["longitude"])
                        accuracy = data.get("accuracy")
                    except (KeyError, ValueError, TypeError):
                        await websocket.send_json({
                            "type": "error",
                            "detail": "Formato inválido. Esperado: {type, latitude, longitude, accuracy?}",
                        })
                        continue

                    if not manager.should_broadcast(user_id_str, lat, lon):
                        continue

                    _upsert_location(db, user.id, eid, lat, lon, accuracy)

                    if not is_organizer and group_id_str:
                        await manager.broadcast_to_group(
                            event_id, group_id_str, user_id_str,
                            {
                                "type": "location",
                                "user_id": user_id_str,
                                "name": user.name,
                                "latitude": lat,
                                "longitude": lon,
                                "accuracy": accuracy,
                            },
                        )

                elif msg_type == "reaction":
                    # Req 16: reacción rápida — broadcast al grupo incluyendo al emisor
                    reaction = data.get("reaction", "").strip()
                    if not reaction:
                        await websocket.send_json({"type": "error", "detail": "El campo 'reaction' es requerido"})
                        continue
                    if len(reaction) > 100:
                        await websocket.send_json({"type": "error", "detail": "Reacción demasiado larga (máx. 100 chars)"})
                        continue

                    if group_id_str:
                        await manager.broadcast_to_group(
                            event_id, group_id_str, None,  # None = incluir al emisor
                            {
                                "type": "reaction",
                                "user_id": user_id_str,
                                "name": user.name,
                                "reaction": reaction,
                            },
                        )

                elif msg_type == "message":
                    # Req 16: mensaje de chat — broadcast al grupo incluyendo al emisor
                    text_content = data.get("text", "").strip()
                    if not text_content:
                        await websocket.send_json({"type": "error", "detail": "El campo 'text' es requerido"})
                        continue
                    if len(text_content) > 100:
                        await websocket.send_json({"type": "error", "detail": "Mensaje demasiado largo (máx. 100 chars)"})
                        continue

                    if group_id_str:
                        await manager.broadcast_to_group(
                            event_id, group_id_str, None,  # None = incluir al emisor
                            {
                                "type": "message",
                                "user_id": user_id_str,
                                "name": user.name,
                                "text": text_content,
                            },
                        )

                else:
                    await websocket.send_json({
                        "type": "error",
                        "detail": f"Tipo de mensaje desconocido: {msg_type}",
                    })

        except WebSocketDisconnect:
            pass
        finally:
            heartbeat_task.cancel()
            # Desconectar de todos los canales en los que estaba registrado
            if is_organizer:
                manager.disconnect(event_id, "__organizers__", user_id_str)
            if group_id_str:
                manager.disconnect(event_id, group_id_str, user_id_str)
            # Liberar slot de conexión
            _ws_release(user_id_str)

    finally:
        db.close()
