"""
Servicio de notificaciones push FCM via Firebase Admin SDK.
Envía notificaciones a dispositivos registrados cuando no están conectados por WS.
"""
import logging
from typing import Optional

logger = logging.getLogger(__name__)

# Firebase Admin SDK — se inicializa lazy para no fallar si no hay credenciales
_firebase_app = None
_fcm_available = False


def _init_firebase():
    """Inicializa Firebase Admin SDK. Solo falla silenciosamente si no hay credenciales."""
    global _firebase_app, _fcm_available
    if _firebase_app is not None:
        return _fcm_available
    try:
        import firebase_admin
        from firebase_admin import credentials
        import os

        # Buscar credenciales en variable de entorno o archivo
        cred_path = os.environ.get("FIREBASE_SERVICE_ACCOUNT_PATH")
        cred_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")

        if cred_json:
            import json
            cred = credentials.Certificate(json.loads(cred_json))
        elif cred_path and os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
        else:
            logger.warning("FCM: No se encontraron credenciales de Firebase. Las notificaciones push estarán deshabilitadas.")
            _fcm_available = False
            return False

        _firebase_app = firebase_admin.initialize_app(cred)
        _fcm_available = True
        logger.info("FCM: Firebase Admin SDK inicializado correctamente")
        return True
    except ImportError:
        logger.warning("FCM: firebase-admin no instalado. Instalar con: pip install firebase-admin")
        _fcm_available = False
        return False
    except Exception as e:
        logger.error(f"FCM: Error al inicializar Firebase: {e}")
        _fcm_available = False
        return False


def send_sos_push(
    tokens: list[str],
    sender_name: str,
    event_id: str,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
) -> int:
    """
    Envía notificación push de SOS a una lista de tokens FCM.
    Retorna el número de mensajes enviados exitosamente.
    """
    if not tokens:
        return 0
    if not _init_firebase():
        return 0

    try:
        from firebase_admin import messaging

        messages = []
        for token in tokens:
            msg = messaging.Message(
                notification=messaging.Notification(
                    title="🆘 Alerta SOS",
                    body=f"{sender_name} necesita ayuda",
                ),
                data={
                    "type": "sos",
                    "user_name": sender_name,
                    "event_id": event_id,
                    "latitude": str(latitude) if latitude else "",
                    "longitude": str(longitude) if longitude else "",
                },
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        channel_id="festisafe_sos",
                        priority="max",
                        default_vibrate_timings=True,
                    ),
                ),
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(
                            sound="default",
                            badge=1,
                            content_available=True,
                        )
                    )
                ),
                token=token,
            )
            messages.append(msg)

        # Enviar en batch (máx 500 por llamada)
        batch_response = messaging.send_each(messages)
        success_count = batch_response.success_count
        if batch_response.failure_count > 0:
            logger.warning(f"FCM: {batch_response.failure_count} mensajes fallaron de {len(tokens)}")
        return success_count
    except Exception as e:
        logger.error(f"FCM: Error al enviar SOS push: {e}")
        return 0


def send_group_join_request_push(
    tokens: list[str],
    requester_name: str,
    group_name: str,
    request_id: str,
) -> int:
    """
    Envía notificación push al admin del grupo cuando alguien solicita unirse.
    """
    if not tokens:
        return 0
    if not _init_firebase():
        return 0

    try:
        from firebase_admin import messaging

        messages = [
            messaging.Message(
                notification=messaging.Notification(
                    title="Nueva solicitud de grupo",
                    body=f"{requester_name} quiere unirse a {group_name}",
                ),
                data={
                    "type": "group_join_request",
                    "requester_name": requester_name,
                    "group_name": group_name,
                    "request_id": request_id,
                },
                android=messaging.AndroidConfig(priority="normal"),
                token=token,
            )
            for token in tokens
        ]
        batch_response = messaging.send_each(messages)
        return batch_response.success_count
    except Exception as e:
        logger.error(f"FCM: Error al enviar join request push: {e}")
        return 0
