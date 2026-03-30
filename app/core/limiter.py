"""
Rate limiting centralizado con slowapi.
Aplica límites por IP para prevenir abuso y ataques de fuerza bruta.
"""
from slowapi import Limiter
from slowapi.util import get_remote_address

# Límite global por defecto: 200 requests/minuto por IP
# Los endpoints sensibles tienen sus propios límites más estrictos
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["200/minute"],
    headers_enabled=True,   # Agrega X-RateLimit-* headers a las respuestas
)
