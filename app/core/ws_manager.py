import math
from datetime import datetime, timedelta
from typing import Dict, Optional
from fastapi import WebSocket

THROTTLE_SECONDS = 10
MIN_MOVEMENT_METERS = 3

# Canal especial para organizadores/admins que escuchan todo el evento
_ORGANIZER_CHANNEL = "__organizers__"


def _haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6_371_000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


class ConnectionManager:
    """
    Conexiones agrupadas:
    - Por Evento: event_id → channel_id → {user_id: WebSocket}
    - Por Tópico (Web): topic → {user_id: WebSocket}
    """

    def __init__(self):
        self._connections: Dict[str, Dict[str, Dict[str, WebSocket]]] = {}
        self._topic_connections: Dict[str, Dict[str, WebSocket]] = {} # Nuevo: para la Web
        self._last_update: Dict[str, datetime] = {}
        self._last_position: Dict[str, tuple[float, float]] = {}

    # ------------------------------------------------------------------
    # Conexión / desconexión
    # ------------------------------------------------------------------

    def connect_topic(self, topic: str, user_id: str, ws: WebSocket):
        """Suscribe una conexión a un tópico (ej: company_uuid)"""
        self._topic_connections.setdefault(topic, {})[user_id] = ws

    def disconnect_topic(self, topic: str, user_id: str):
        try:
            del self._topic_connections[topic][user_id]
            if not self._topic_connections[topic]:
                del self._topic_connections[topic]
        except KeyError:
            pass

    async def broadcast_to_topic(self, topic: str, message: dict):
        """Envía un mensaje a todos los suscritos a un tópico (Portal Web)"""
        conns = self._topic_connections.get(topic, {})
        dead = []
        for uid, ws in conns.items():
            try:
                await ws.send_json(message)
            except Exception:
                dead.append(uid)
        for uid in dead:
            self.disconnect_topic(topic, uid)

    def connect(self, event_id: str, channel: str, user_id: str, ws: WebSocket):
        self._connections.setdefault(event_id, {}).setdefault(channel, {})[user_id] = ws

    def connect_organizer(self, event_id: str, user_id: str, ws: WebSocket):
        """Registra al organizador/admin en el canal de evento completo."""
        self.connect(event_id, _ORGANIZER_CHANNEL, user_id, ws)

    def disconnect(self, event_id: str, channel: str, user_id: str):
        try:
            del self._connections[event_id][channel][user_id]
            if not self._connections[event_id][channel]:
                del self._connections[event_id][channel]
            if not self._connections[event_id]:
                del self._connections[event_id]
        except KeyError:
            pass
        self._last_update.pop(user_id, None)
        self._last_position.pop(user_id, None)

    # ------------------------------------------------------------------
    # Throttle / movimiento
    # ------------------------------------------------------------------

    def should_broadcast(self, user_id: str, lat: float, lon: float) -> bool:
        now = datetime.utcnow()
        last = self._last_update.get(user_id)
        if last and (now - last) < timedelta(seconds=THROTTLE_SECONDS):
            return False
        prev = self._last_position.get(user_id)
        if prev and _haversine_meters(prev[0], prev[1], lat, lon) < MIN_MOVEMENT_METERS:
            return False
        self._last_update[user_id] = now
        self._last_position[user_id] = (lat, lon)
        return True

    # ------------------------------------------------------------------
    # Broadcast
    # ------------------------------------------------------------------

    async def broadcast_to_group(
        self,
        event_id: str,
        group_id: str,
        sender_user_id: str,
        message: dict,
    ):
        """Envía a todos los miembros del grupo excepto al emisor."""
        await self._send_to_channel(event_id, group_id, message, exclude=sender_user_id)

    async def broadcast_to_organizers(self, event_id: str, message: dict):
        """Envía a todos los organizadores/admins conectados al evento."""
        await self._send_to_channel(event_id, _ORGANIZER_CHANNEL, message)

    async def broadcast_sos(
        self,
        event_id: str,
        group_id: str,
        sender_user_id: str,
        message: dict,
    ):
        """
        Broadcast SOS: llega a todo el grupo (incluido el emisor para confirmación)
        y a todos los organizadores conectados.
        """
        await self._send_to_channel(event_id, group_id, message)
        await self._send_to_channel(event_id, _ORGANIZER_CHANNEL, message)

    async def _send_to_channel(
        self,
        event_id: str,
        channel: str,
        message: dict,
        exclude: Optional[str] = None,
    ):
        conns = self._connections.get(event_id, {}).get(channel, {})
        dead = []
        for uid, ws in conns.items():
            if uid == exclude:
                continue
            try:
                await ws.send_json(message)
            except Exception:
                dead.append(uid)
        for uid in dead:
            self.disconnect(event_id, channel, uid)


manager = ConnectionManager()
