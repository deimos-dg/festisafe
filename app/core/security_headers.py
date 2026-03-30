"""
Middleware de headers de seguridad HTTP.
Aplica las cabeceras recomendadas por OWASP para hardening de la API.
"""
import uuid
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """
    Agrega headers de seguridad a todas las respuestas HTTP.
    Referencia: https://owasp.org/www-project-secure-headers/
    """

    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)

        # Evita que el navegador infiera el tipo MIME
        response.headers["X-Content-Type-Options"] = "nosniff"

        # Bloquea clickjacking
        response.headers["X-Frame-Options"] = "DENY"

        # Fuerza HTTPS (1 año, incluye subdominios)
        response.headers["Strict-Transport-Security"] = (
            "max-age=31536000; includeSubDomains; preload"
        )

        # Política de referrer mínima
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

        # Deshabilita características del navegador no necesarias
        response.headers["Permissions-Policy"] = (
            "geolocation=(), microphone=(), camera=(), payment=()"
        )

        # Content Security Policy — API REST solo sirve JSON, no HTML
        response.headers["Content-Security-Policy"] = (
            "default-src 'none'; frame-ancestors 'none'; form-action 'none'"
        )

        # Bloquea acceso de Flash/PDF cross-domain (previene ataques de cross-domain)
        response.headers["X-Permitted-Cross-Domain-Policies"] = "none"

        # Elimina headers que revelan el stack tecnológico y puertos internos
        response.headers.pop("server", None)
        response.headers.pop("x-powered-by", None)
        response.headers.pop("x-aspnet-version", None)
        response.headers.pop("x-aspnetmvc-version", None)

        # Trazabilidad: X-Request-ID para correlacionar logs sin exponer internos
        if "X-Request-ID" not in response.headers:
            response.headers["X-Request-ID"] = str(uuid.uuid4())

        # Cache: no almacenar respuestas de la API
        if request.url.path.startswith("/api/"):
            response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, private"
            response.headers["Pragma"] = "no-cache"

        return response
