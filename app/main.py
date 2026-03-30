import logging
import asyncio
import uuid
from fastapi import FastAPI, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from sqlalchemy.orm import Session
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from fastapi.responses import JSONResponse
from fastapi.openapi.utils import get_openapi
from slowapi.errors import RateLimitExceeded
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response as StarletteResponse

from app.core.config import settings
from app.core.database import get_db, create_tables
from app.core.scheduler import start_scheduler
from app.core.limiter import limiter
from app.core.security_headers import SecurityHeadersMiddleware
from app.core.audit_log import log_security_event, AuditEvent

from app.api.v1.endpoints import (
    auth, health, users, gps, groups,
    group_members, events, ws, sos, admin,
)

# ---------------------------------------------------------
# Logging estructurado
# ---------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "msg": %(message)s}',
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------
# App
# ---------------------------------------------------------
_docs_url = "/docs" if settings.ENABLE_DOCS else None
_redoc_url = "/redoc" if settings.ENABLE_DOCS else None
_openapi_url = "/openapi.json" if settings.ENABLE_DOCS else None

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    debug=settings.DEBUG,
    docs_url=_docs_url,
    redoc_url=_redoc_url,
    openapi_url=_openapi_url,
)

app.state.limiter = limiter

# ---------------------------------------------------------
# Startup
# ---------------------------------------------------------
@app.on_event("startup")
async def startup_event():
    create_tables()
    start_scheduler()
    logger.info('"FestiSafe API iniciada correctamente"')


# ---------------------------------------------------------
# Middlewares (orden importa: primero los más externos)
# ---------------------------------------------------------

# 1. TrustedHostMiddleware — previene ataques de Host header injection
#    y enmascaramiento de puertos internos vía Host manipulation
_allowed_hosts = settings.ALLOWED_HOSTS if hasattr(settings, "ALLOWED_HOSTS") and settings.ALLOWED_HOSTS else ["*"]
app.add_middleware(TrustedHostMiddleware, allowed_hosts=_allowed_hosts)


# 2. Anti-Slowloris: timeout de lectura del body para prevenir conexiones lentas
class SlowlorisProtectionMiddleware(BaseHTTPMiddleware):
    """
    Previene ataques Slowloris imponiendo un timeout máximo para recibir
    el body completo del request. Si el cliente tarda más de REQUEST_TIMEOUT
    segundos en enviar el body, se cierra la conexión con 408.
    """
    REQUEST_TIMEOUT = 30  # segundos

    async def dispatch(self, request: Request, call_next):
        try:
            return await asyncio.wait_for(call_next(request), timeout=self.REQUEST_TIMEOUT)
        except asyncio.TimeoutError:
            ip = request.client.host if request.client else "unknown"
            log_security_event(
                AuditEvent.RATE_LIMIT_HIT,
                ip=ip,
                detail=f"Timeout de request en {request.url.path} — posible Slowloris",
            )
            return JSONResponse(
                status_code=408,
                content={"detail": "Request timeout"},
            )

app.add_middleware(SlowlorisProtectionMiddleware)


# 3. Limitar tamaño del body para prevenir DoS
class MaxBodySizeMiddleware(BaseHTTPMiddleware):
    """Rechaza requests con body mayor a MAX_REQUEST_BODY_SIZE bytes."""
    async def dispatch(self, request: Request, call_next):
        content_length = request.headers.get("content-length")
        if content_length:
            if int(content_length) > settings.MAX_REQUEST_BODY_SIZE:
                return JSONResponse(
                    status_code=413,
                    content={"detail": "Request demasiado grande"},
                )
        return await call_next(request)

app.add_middleware(MaxBodySizeMiddleware)


# 4. Headers de seguridad HTTP
app.add_middleware(SecurityHeadersMiddleware)


# 5. CORS — orígenes explícitos, nunca wildcard en producción
_cors_origins = settings.BACKEND_CORS_ORIGINS or (["*"] if settings.DEBUG else [])
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept", "X-Request-ID"],
    expose_headers=["X-Request-ID"],
    max_age=600,
)

# ---------------------------------------------------------
# Routers
# ---------------------------------------------------------
app.include_router(health.router)
app.include_router(ws.router)
app.include_router(auth.router, prefix=settings.API_V1_STR)
app.include_router(users.router, prefix=settings.API_V1_STR)
app.include_router(events.router, prefix=settings.API_V1_STR)
app.include_router(gps.router, prefix=settings.API_V1_STR)
app.include_router(groups.router, prefix=settings.API_V1_STR)
app.include_router(group_members.router, prefix=settings.API_V1_STR)
app.include_router(sos.router, prefix=settings.API_V1_STR)
app.include_router(admin.router, prefix=settings.API_V1_STR)


# ---------------------------------------------------------
# Root — no exponer información sensible
# ---------------------------------------------------------
@app.get("/")
def root():
    return {"status": "ok", "version": settings.VERSION}


# ---------------------------------------------------------
# Health con DB — sin exponer detalles del error
# ---------------------------------------------------------
@app.get("/health/db")
def health_db(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
        return {"status": "healthy"}
    except Exception:
        logger.error("Health check DB failed", exc_info=True)
        return JSONResponse(
            status_code=503,
            content={"status": "unhealthy"},
        )


# ---------------------------------------------------------
# Exception handlers
# ---------------------------------------------------------
@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    ip = request.client.host if request.client else "unknown"
    log_security_event(
        AuditEvent.RATE_LIMIT_HIT,
        ip=ip,
        detail=f"Rate limit en {request.url.path}",
    )
    return JSONResponse(
        status_code=429,
        content={"detail": "Demasiados intentos. Intenta más tarde"},
        headers={"Retry-After": "60"},
    )


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError):
    errors = [
        {"field": ".".join(str(l) for l in e["loc"]), "message": e["msg"]}
        for e in exc.errors()
    ]
    return JSONResponse(
        status_code=422,
        content={"detail": "Error de validación", "errors": errors},
    )


@app.exception_handler(SQLAlchemyError)
async def db_error_handler(request: Request, exc: SQLAlchemyError):
    logger.error(f"Database error en {request.url.path}: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Error interno del servidor"},
    )


@app.exception_handler(Exception)
async def generic_error_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled error en {request.url.path}: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Error interno del servidor"},
    )


# ---------------------------------------------------------
# OpenAPI con JWT (solo si docs habilitados)
# ---------------------------------------------------------
def custom_openapi():
    if app.openapi_schema:
        return app.openapi_schema

    schema = get_openapi(
        title=settings.PROJECT_NAME,
        version=settings.VERSION,
        description="FestiSafe API — Seguridad en festivales",
        routes=app.routes,
    )

    schema["components"]["securitySchemes"] = {
        "BearerAuth": {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
        }
    }
    schema["security"] = [{"BearerAuth": []}]
    app.openapi_schema = schema
    return app.openapi_schema


if settings.ENABLE_DOCS:
    app.openapi = custom_openapi
