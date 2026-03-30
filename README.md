# FestiSafe

Plataforma de seguridad para festivales de música. Compuesta por una API REST/WebSocket en FastAPI y una app móvil en Flutter.

---

## Estructura del proyecto

```
festisafe/
├── app/                        # Backend (FastAPI)
│   ├── api/
│   │   ├── deps.py
│   │   └── v1/endpoints/
│   ├── core/
│   ├── crud/
│   ├── db/
│   │   └── models/
│   ├── schemas/
│   └── main.py
├── festisafe_app/              # Frontend (Flutter)
│   ├── lib/
│   │   ├── core/
│   │   ├── data/
│   │   ├── presentation/
│   │   └── providers/
│   ├── test/properties/
│   └── android/
├── deploy/
├── Dockerfile
└── .env
```

---

## Backend

### Tecnologías

| Componente | Tecnología |
|---|---|
| Framework | FastAPI 0.110+ |
| ORM | SQLAlchemy 2.0 |
| Base de datos | PostgreSQL (RDS en producción) |
| Autenticación | JWT (access 15 min + refresh 7 días) |
| Hashing | bcrypt (passlib) |
| WebSocket | FastAPI WebSocket nativo |
| Tareas periódicas | APScheduler |
| Rate limiting | slowapi |
| Validación | Pydantic v2 |
| Servidor | Uvicorn + Gunicorn |


### `app/main.py`

Entrypoint de FastAPI. Registra todos los routers bajo el prefijo `/api/v1`, configura CORS (permite todos los orígenes en desarrollo), inicializa el rate limiter de slowapi, y llama a `create_tables()` en el evento `startup` para crear tablas y ejecutar migraciones automáticas.

### `app/api/deps.py`

Dependencias de autenticación reutilizables en todos los endpoints:

- `get_current_user` — extrae y valida el JWT del header `Authorization: Bearer`, verifica que no esté revocado, y retorna el usuario activo. Lanza 401 si el token es inválido o expirado.
- `get_current_active_user` — igual que el anterior pero además verifica `is_active=True` y que no tenga `must_change_password=True`.
- `get_current_user_allow_password_change` — variante que permite pasar aunque `must_change_password=True`, usada exclusivamente en el endpoint de cambio de contraseña.
- `require_roles(roles)` — factory que retorna una dependencia que verifica que el usuario tenga uno de los roles especificados (`user`, `organizer`, `admin`). Lanza 403 si no cumple.

---

### Endpoints — `app/api/v1/endpoints/`

#### `auth.py` — Autenticación

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/auth/register` | Crea un nuevo usuario. Valida email único, hashea contraseña con bcrypt. Rate limit: 5/min. |
| POST | `/auth/login` | Autentica con email+contraseña. Verifica bloqueo temporal, registra intentos fallidos, retorna access+refresh token. Rate limit: 10/min. |
| POST | `/auth/refresh` | Renueva tokens usando un refresh token válido. Revoca el refresh token usado (rotación). Rate limit: 20/min. |
| POST | `/auth/logout` | Revoca el access token actual añadiendo su JTI a la blacklist. |
| POST | `/auth/guest-login` | Canjea un código de 6 dígitos, crea cuenta de invitado automáticamente, une al evento y retorna tokens. Rate limit: 10/min. |
| POST | `/auth/convert-guest` | Convierte cuenta de invitado en permanente asignando email, contraseña y teléfono reales. |

La función `check_user_status()` verifica bloqueo temporal (`lock_until`) con desbloqueo automático si el tiempo ya pasó, y el flag `must_change_password`.

#### `users.py` — Usuarios

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/users/me` | Retorna el perfil del usuario autenticado. |
| PATCH | `/users/me` | Actualiza nombre y/o teléfono. |
| POST | `/users/me/change-password` | Cambia contraseña validando la actual, verifica complejidad, resetea flags de bloqueo y actualiza `password_changed_at` para invalidar tokens anteriores. |
| GET | `/users/{user_id}` | Perfil público de cualquier usuario por UUID. |
| PATCH | `/users/{user_id}/role` | Cambia el rol de un usuario. Solo admins. No permite auto-cambio. |


#### `events.py` — Eventos

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/events/` | Crea evento. Solo organizadores/admins. Valida que `ends_at > starts_at` y `expires_at >= ends_at`. El evento se crea inactivo. |
| PATCH | `/events/{id}` | Edita campos del evento. Solo el organizador dueño o admin. |
| DELETE | `/events/{id}` | Elimina el evento. Solo el organizador dueño o admin. |
| POST | `/events/{id}/activate` | Activa el evento para que los usuarios puedan unirse. |
| POST | `/events/{id}/deactivate` | Desactiva el evento. |
| GET | `/events/my` | Lista los eventos en los que el usuario está inscrito activamente. |
| GET | `/events/search` | Busca eventos activos por nombre o ubicación (query param `q`). |
| GET | `/events/public` | Búsqueda pública de eventos activos. No requiere autenticación. |
| GET | `/events/organized` | Lista los eventos creados por el organizador autenticado. |
| GET | `/events/{id}` | Detalle de un evento por UUID. |
| POST | `/events/{id}/join` | Une al usuario al evento. Verifica que esté activo, no expirado y con cupo disponible. Permite reincorporación si ya salió. |
| POST | `/events/{id}/leave` | Marca la participación como inactiva con timestamp de salida. |
| GET | `/events/{id}/participants` | Lista participantes activos del evento con nombre. Solo miembros o admins. |
| POST | `/events/{id}/guest-code` | Genera código numérico de 6 dígitos para invitados. Configurable: `max_uses` (1-100) y `expires_hours` (1-168). Solo organizadores/admins dueños del evento. |

#### `groups.py` — Grupos

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/groups/` | Crea un grupo en un evento. El creador se convierte en admin y primer miembro. Un usuario solo puede tener un grupo por evento. |
| GET | `/groups/my/{event_id}` | Retorna el grupo al que pertenece el usuario en el evento dado. |
| GET | `/groups/{id}` | Detalle del grupo: nombre, evento, admin, estado, capacidad. |
| GET | `/groups/{id}/members` | Lista miembros activos con nombre, rol y fecha de ingreso. |
| POST | `/groups/{id}/transfer-admin` | Transfiere la administración a otro miembro. Baja el rol del admin actual a `member`. |
| POST | `/groups/{id}/leave` | Sale del grupo. Si el admin quiere salir con más miembros, debe transferir primero. Si es el último miembro, elimina el grupo. |
| DELETE | `/groups/{id}` | Elimina el grupo. Solo el admin del grupo o un admin del sistema. |

#### `group_members.py` — Miembros de grupo

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/group-members/add/{group_id}` | Agrega un usuario al grupo. Solo el admin del grupo puede hacerlo. Verifica que el usuario pertenezca al evento, que el grupo no esté lleno ni cerrado. Permite reactivar miembros que salieron. |
| DELETE | `/group-members/remove/{group_id}/{user_id}` | Elimina un miembro. El admin puede expulsar a cualquiera (excepto a sí mismo). Un miembro puede salir por su cuenta. |


#### `gps.py` — Ubicación GPS

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/gps/location/{event_id}` | Actualiza o crea la última ubicación del usuario en el evento (fallback HTTP cuando el WebSocket no está disponible). Hace upsert en `user_last_locations`. |
| GET | `/gps/location/{event_id}` | Retorna las últimas ubicaciones visibles de todos los participantes del evento. Hace JOIN con `users` para incluir el nombre. |
| PATCH | `/gps/visibility/{event_id}` | Activa o desactiva la visibilidad del usuario en el mapa del evento (`is_visible`). |

#### `sos.py` — Alertas SOS

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/sos/{event_id}/activate` | Activa la alerta SOS del usuario. Actualiza/crea su ubicación en ese momento. Hace broadcast inmediato al grupo (incluyendo al emisor) y a los organizadores vía WebSocket. |
| POST | `/sos/{event_id}/deactivate` | Desactiva la alerta SOS. Notifica cancelación al grupo y organizadores. |
| POST | `/sos/{event_id}/escalate/{user_id}` | Escala el SOS de un usuario (marca `sos_escalated=True`). Solo organizadores/admins. Broadcast de `sos_escalated` al grupo y organizadores. |
| GET | `/sos/{event_id}/active` | Lista todos los participantes con `sos_active=True` en el evento. Solo miembros del evento. |

#### `ws.py` — WebSocket

Endpoint: `WS /ws/location/{event_id}?token=<access_token>`

Flujo de conexión:
1. Autentica el JWT y verifica que el usuario esté activo y no bloqueado.
2. Valida que el evento exista y esté activo.
3. Verifica que el usuario sea participante activo del evento.
4. Determina si el usuario pertenece a un grupo o es organizador.
5. Registra la conexión en el `ConnectionManager` y envía `{"type": "connected", "group_id": ..., "role": ...}`.
6. Inicia una tarea de heartbeat que envía `{"type": "ping"}` cada 30 segundos.

Mensajes entrantes soportados:

| Tipo | Campos | Acción |
|---|---|---|
| `location` | `latitude`, `longitude`, `accuracy?` | Persiste ubicación, aplica throttle (10s / 3m mínimo), broadcast al grupo. |
| `pong` | — | Respuesta al heartbeat del servidor. No genera acción. |
| `reaction` | `reaction` (máx. 100 chars) | Broadcast al grupo incluyendo al emisor. |
| `message` | `text` (máx. 100 chars) | Broadcast al grupo incluyendo al emisor. |

Códigos de cierre WebSocket: `4001` token inválido, `4003` acceso denegado.

#### `admin.py` — Administración

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/admin/users` | Lista usuarios con filtros: `role`, `is_active`, búsqueda por nombre/email (`q`). Paginado. Solo admins. |
| PATCH | `/admin/users/{id}/activate` | Activa cuenta y desbloquea. |
| PATCH | `/admin/users/{id}/deactivate` | Desactiva cuenta. No permite auto-desactivación. |
| PATCH | `/admin/users/{id}/unlock` | Desbloquea cuenta bloqueada por fuerza bruta, resetea intentos y `must_change_password`. |
| GET | `/admin/events` | Lista todos los eventos con conteo de participantes activos. Filtrable por `is_active`. |
| GET | `/admin/stats` | Estadísticas globales: total/activos/bloqueados usuarios, total/activos eventos, SOS activos. |

#### `health.py` — Health check

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/health/` | Retorna `{"status": "ok", "service": "FestiSafe API", "version": "2.1.0"}`. Usado por el ALB para health checks. |

---

### `app/core/`

#### `config.py`
Configuración de la aplicación usando `pydantic-settings`. Lee variables de entorno: `SECRET_KEY`, `DATABASE_URL`, `DEBUG`, `ACCESS_TOKEN_EXPIRE_MINUTES` (default 15), `REFRESH_TOKEN_EXPIRE_DAYS` (default 7).

#### `database.py`
Inicialización de la BD al arrancar:
- `create_tables()` — llama a `Base.metadata.create_all()` para crear todas las tablas si no existen.
- `_run_migrations()` — ejecuta migraciones manuales SQL (lista de `ALTER TABLE` / `CREATE INDEX`). Cada migración usa `IF NOT EXISTS` para ser idempotente. Actualmente agrega la columna `is_guest` y su índice a la tabla `users`.

#### `security.py`
Funciones de seguridad:
- `hash_password(password)` / `verify_password(plain, hashed)` — bcrypt via passlib.
- `create_access_token(user_id, email)` — JWT con `type=access`, `jti` UUID único, expiración configurable.
- `create_refresh_token(user_id, email)` — JWT con `type=refresh`, `jti` UUID único, expiración 7 días.
- `decode_token(token)` — decodifica y valida firma y expiración. Lanza 401 si inválido.
- `register_failed_attempt(user, db)` — incrementa `failed_login_attempts`. A los 3 intentos bloquea 3 minutos. A los 6+ activa `must_change_password`.
- `reset_login_attempts(user, db)` — resetea contador tras login exitoso.

#### `ws_manager.py`
`ConnectionManager` — gestiona todas las conexiones WebSocket activas:
- `connect(event_id, group_id, user_id, ws)` — registra conexión de miembro de grupo.
- `connect_organizer(event_id, user_id, ws)` — registra conexión de organizador.
- `disconnect(event_id, channel, user_id)` — elimina conexión.
- `broadcast_to_group(event_id, group_id, exclude_user_id, message)` — envía a todos los miembros del grupo. Si `exclude_user_id=None`, incluye al emisor.
- `broadcast_sos(event_id, group_id, sender_id, message)` — broadcast SOS al grupo sin excluir al emisor.
- `broadcast_to_organizers(event_id, message)` — envía solo a organizadores conectados.
- `should_broadcast(user_id, lat, lon)` — throttle: retorna `False` si han pasado menos de 10 segundos desde el último broadcast O si el movimiento es menor a 3 metros.

#### `scheduler.py`
Tareas periódicas con APScheduler:
- Cada 5 minutos: desactiva eventos cuyo `expires_at` ya pasó.
- Cada 10 minutos: elimina tokens revocados expirados de la blacklist.
- Cada hora: desbloquea cuentas cuyo `lock_until` ya pasó.

#### `limiter.py`
Instancia global de `slowapi.Limiter` con clave por IP (`get_remote_address`). Se aplica con el decorador `@limiter.limit("N/minute")` en endpoints sensibles.

#### `validators.py`
`validate_password(password)` — valida que la contraseña tenga mínimo 12 caracteres, al menos una mayúscula, una minúscula, un dígito y un carácter especial. Lanza `ValueError` con mensaje descriptivo si no cumple.


---

### `app/crud/`

#### `user.py`
- `get_user_by_email(db, email)` — busca usuario por email (case-insensitive).
- `get_user_by_id(db, user_id)` — busca por UUID.
- `create_user(db, data)` — crea usuario con los campos dados, hace commit y refresh.

#### `revoked_token.py`
- `revoke_token(jti, db)` — inserta el JTI en la tabla `revoked_tokens` con timestamp.
- `is_token_revoked(db, jti)` — consulta si el JTI existe en la blacklist.

#### `token.py`
Helpers adicionales para verificación de tokens en el flujo de autenticación.

---

### `app/db/models/`

#### `user.py`
Tabla `users`. Campos: `id` (UUID PK), `email` (único), `hashed_password`, `name`, `phone`, `role` (enum: `user`/`organizer`/`admin`), `is_active`, `is_locked`, `is_guest`, `failed_login_attempts`, `lock_until`, `must_change_password`, `password_changed_at`, `created_at`.

#### `event.py`
Tabla `events`. Campos: `id`, `name`, `description`, `location_name`, `latitude`, `longitude`, `starts_at`, `ends_at`, `expires_at`, `max_participants`, `organizer_id` (FK → users), `is_active`, `created_at`. Método `close_event()` que desactiva el evento.

#### `event_participant.py`
Tabla `event_participants`. Relación usuario ↔ evento. Campos: `id`, `user_id` (FK), `event_id` (FK), `role` (`attendee`/`organizer`), `is_active`, `joined_at`, `left_at`, `latitude`, `longitude`, `location_updated_at`, `sos_active`, `sos_started_at`, `sos_escalated`. Unique constraint en `(user_id, event_id)`.

#### `group.py`
Tabla `groups`. Campos: `id`, `name`, `event_id` (FK), `admin_id` (FK → users), `max_members` (default 8), `is_closed`, `created_at`.

#### `group_member.py`
Tabla `group_members`. Relación participant ↔ grupo. Campos: `id`, `group_id` (FK), `event_participant_id` (FK), `role` (`member`/`admin`), `is_active`, `joined_at`, `left_at`. Unique constraint en `(group_id, event_participant_id)`. Relationship `group` para acceso directo al objeto Group.

#### `guest_code.py`
Tabla `guest_codes`. Campos: `id`, `code` (6 dígitos, único), `event_id` (FK), `created_by` (FK → users, nullable), `max_uses`, `used_count`, `expires_at`, `is_active`, `created_at`. Propiedad `remaining_uses` y método `is_valid()` que verifica activo + usos restantes + no expirado.

#### `user_last_location.py`
Tabla `user_last_locations`. Última ubicación conocida por usuario+evento. Campos: `id`, `user_id` (FK), `event_id` (FK), `latitude`, `longitude`, `accuracy`, `speed`, `heading`, `is_visible`, `updated_at`. Unique constraint en `(user_id, event_id)`. Índices compuestos para lookup eficiente. Método `update_location()` que actualiza coordenadas y timestamp.

#### `login_attempt.py`
Tabla `login_attempts`. Registro de intentos de login por IP para análisis de seguridad.

#### `revoked_token.py`
Tabla `revoked_tokens`. Blacklist de JTIs. Campos: `id`, `jti` (único, indexado), `revoked_at`.

---

### `app/schemas/`

Schemas Pydantic v2 para validación de requests y serialización de responses.

#### `auth.py`
- `UserCreate` — registro: `email`, `password` (validado por `validators.py`), `confirm_password`, `name`, `phone?`.
- `LoginRequest` — login: `email`, `password`.
- `GuestLoginRequest` — acceso invitado: `code` (6 dígitos).
- `ConvertGuestRequest` — conversión: `email`, `password`, `phone?`.
- `GuestCodeResponse` — respuesta de generación de código: `code`, `expires_at`, `remaining_uses`, `event_id`.

#### `user.py`
- `UserResponse` — perfil público: `id`, `email`, `name`, `phone`, `role`, `is_active`, `is_guest`, `created_at`.
- `UserUpdate` — actualización parcial: `name?`, `phone?`.
- `ChangePasswordRequest` — cambio de contraseña: `current_password`, `new_password`.

#### `event.py`
- `EventCreate` — creación: todos los campos del evento con validaciones de fechas.
- `EventUpdate` — actualización parcial (todos opcionales).
- `EventResponse` — respuesta completa del evento.
- `EventParticipantResponse` — participante con nombre incluido.

#### `group.py`
- `GroupCreate`, `GroupResponse`, `GroupMemberResponse`.

#### `location.py`
- `LocationCreate` — `latitude`, `longitude`, `accuracy?`.
- `LocationOut` — respuesta con `user_id`, `name`, `latitude`, `longitude`, `accuracy`, `is_visible`, `updated_at`.

#### `sos.py`
- `SOSActivateRequest` — `latitude`, `longitude`, `accuracy?`, `battery_level?`.
- `SOSStatusResponse` — estado del participante: `user_id`, `event_id`, `sos_active`, `sos_started_at`, `sos_escalated`.


---

## Frontend (Flutter)

### Tecnologías

| Componente | Tecnología |
|---|---|
| Framework | Flutter 3.29+ / Dart 3.3+ |
| Estado | Riverpod 2.x (StateNotifier) |
| Navegación | go_router 13.x |
| HTTP | Dio 5.x |
| WebSocket | web_socket_channel |
| Almacenamiento seguro | flutter_secure_storage |
| Mapas | flutter_map + OpenStreetMap |
| GPS | geolocator |
| Notificaciones | flutter_local_notifications |
| QR | mobile_scanner + qr_flutter |
| Batería | battery_plus |
| Brújula | sensors_plus |

### Arquitectura

```
providers/          ← Estado global (Riverpod StateNotifier)
    ↓
data/services/      ← Lógica de negocio + llamadas HTTP/WS
    ↓
data/models/        ← Modelos de datos (fromJson/toJson)
    ↓
data/storage/       ← Persistencia local (tokens, preferencias)
```

Las pantallas (`presentation/screens/`) consumen providers via `ref.watch()` / `ref.read()`.

---

### `festisafe_app/lib/core/`

#### `constants.dart`
Clase `AppConstants` con todas las constantes globales de la app:
- `apiBaseUrl` / `wsBaseUrl` — URLs del backend en producción (ALB de AWS).
- `connectTimeout` (10s) / `receiveTimeout` (15s) — timeouts de Dio.
- `maxGroupMembers` (8) — límite de miembros por grupo.
- `locationIntervalNormal` (10s) / `locationIntervalLowBattery` (30s) — frecuencia de envío GPS según nivel de batería.
- `locationFallbackInterval` (30s) — intervalo del fallback HTTP cuando el WS no está disponible.
- `wsReconnectBase` (2s) / `wsReconnectMax` (60s) — parámetros de backoff exponencial para reconexión WS.
- `batteryLowThreshold` (20%) / `batteryRestoreThreshold` (25%) / `batteryCriticalThreshold` (10%) — umbrales de batería.
- `markerDimMinutes` (5) / `markerNoSignalMinutes` (15) — tiempo sin actualización para atenuar/ocultar marcadores en el mapa.
- `chatMaxLength` (100) / `reactionBannerSeconds` (3) — límites del chat.
- `wsCloseInvalidToken` (4001) / `wsCloseAccessDenied` (4003) — códigos de cierre WebSocket.

#### `router/app_router.dart`
`routerProvider` — instancia de `GoRouter` con:
- Rutas públicas: `/` (WelcomeScreen), `/login`, `/register`.
- Rutas protegidas: `/home`, `/profile`, `/events`, `/events/:eventId`, `/groups/:groupId`, `/map/:eventId`, `/compass/:userId`.
- Rutas de organizador: `/organizer/:eventId`, `/qr/:eventId` — redirigen a `/home` si el usuario no es organizador.
- Lógica de redirección: si no autenticado y ruta protegida → `/`; si autenticado y ruta pública → `/home`. Acepta tanto `AuthAuthenticated` como `AuthGuest` como estados autenticados.

#### `theme/app_theme.dart`
Configura `ThemeData` con Material 3, `colorSchemeSeed: Color(0xFF0D1B4B)` (azul marino), modo oscuro por defecto. Aplica la paleta seleccionada por el usuario desde `themeProvider`.

#### `theme/color_palettes.dart`
Define 6 paletas de colores predefinidas seleccionables desde la pantalla de perfil.


---

### `festisafe_app/lib/providers/`

#### `auth_provider.dart`
`AuthNotifier` (StateNotifier) con estados: `AuthInitial`, `AuthLoading`, `AuthAuthenticated(user)`, `AuthGuest(user, eventId)`, `AuthUnauthenticated`, `AuthError(message)`.

Métodos:
- `checkSession()` — al arrancar la app, valida el token almacenado y carga el perfil si es válido.
- `login(email, password)` — llama a `AuthService.login()`, luego `getMe()`, transiciona a `AuthAuthenticated`.
- `register(name, email, password, phone?)` — registra y transiciona a `AuthUnauthenticated` (requiere login posterior).
- `guestLogin(code)` — canjea código de 6 dígitos, transiciona a `AuthGuest` con el `eventId` del evento.
- `convertGuest(email, password, phone?)` — convierte cuenta invitado, transiciona a `AuthAuthenticated`.
- `logout()` — llama a `AuthService.logout()`, transiciona a `AuthUnauthenticated`.

#### `event_provider.dart`
Providers de solo lectura basados en `FutureProvider`:
- `eventListProvider(query?)` — busca eventos activos con filtro opcional de texto.
- `myEventsProvider` — eventos en los que el usuario está inscrito.
- `organizedEventsProvider` — eventos creados por el organizador autenticado.

#### `group_provider.dart`
`GroupNotifier` con estado `GroupState { group?, isLoading, error? }`.

Métodos:
- `createGroup(eventId, name)` — crea grupo y actualiza estado.
- `loadMembers(groupId)` — carga miembros y aplica cap de `AppConstants.maxGroupMembers` (Propiedad 7 de PBT).
- `transferAdmin(groupId, newAdminId)` — transfiere admin y recarga miembros.
- `leaveGroup(groupId)` / `deleteGroup(groupId)` — limpia el estado del grupo.
- `setGroup(group)` — establece el grupo directamente (usado al recibir datos del WS).

#### `location_provider.dart`
`LocationNotifier` con estado `LocationState { currentPosition?, isTracking, isVisible }`.

- `startTracking()` — inicia stream GPS con intervalo adaptativo según nivel de batería (lee `batteryProvider`). Intervalo normal: 10s, batería baja (<20%): 30s.
- `stopTracking()` — cancela el stream.

`MemberLocationsNotifier` — mapa `userId → MemberLocation` con las últimas ubicaciones de los miembros del grupo recibidas por WebSocket. Métodos: `updateLocation()`, `removeLocation()`, `clear()`.

#### `ws_provider.dart`
`WsNotifier` con estado `WsConnectionState` (enum: `disconnected`, `connecting`, `connected`, `reconnecting`).

- `connect(eventId, token)` — delega a `WsClient.connect()`.
- `disconnect()` — cierra la conexión.
- `sendLocation(lat, lng, accuracy?)` — envía mensaje `type=location`.
- `sendReaction(reaction)` — envía mensaje `type=reaction`.
- `sendMessage(text)` — envía mensaje `type=message`.
- `messageStream` — stream de `WsMessage` para que las pantallas reaccionen a mensajes entrantes.

`wsClientProvider` — instancia singleton de `WsClient` con dispose automático.

#### `sos_provider.dart`
`SosNotifier` con estado `SosState { isSosActive, activeAlerts: List<SosAlert> }`.

- `setSosActive(bool)` — actualiza si el usuario actual tiene SOS activo.
- `onSosReceived(alert)` — agrega o actualiza alerta en la lista (deduplicación por `userId`).
- `onSosCancelled(userId)` — elimina alerta de la lista.
- `onSosEscalated(userId)` — marca alerta como escalada.
- `setActiveAlerts(alerts)` — carga inicial de alertas activas desde el endpoint REST.

#### Otros providers

| Provider | Tipo | Descripción |
|---|---|---|
| `chatProvider` | StateNotifier | Lista de `ChatMessage` del grupo. Agrega mensajes recibidos por WS. |
| `batteryProvider` | StreamProvider | Nivel de batería actual (%) usando `battery_plus`. |
| `themeProvider` | StateNotifier | Paleta de colores activa. Persiste en `flutter_secure_storage`. |


---

### `festisafe_app/lib/data/`

#### `models/`

| Archivo | Modelo | Campos principales |
|---|---|---|
| `user.dart` | `UserModel` | `id`, `email`, `name`, `phone`, `role`, `isActive`, `isGuest`. Getters: `isOrganizer`, `isAdmin`. |
| `event.dart` | `EventModel` | `id`, `name`, `description`, `locationName`, `latitude`, `longitude`, `startsAt`, `endsAt`, `expiresAt`, `maxParticipants`, `isActive`, `organizerId`. |
| `group.dart` | `GroupModel` | `id`, `eventId`, `name`, `members: List<GroupMember>`. |
| `group_member.dart` | `GroupMember` | `userId`, `name`, `role`, `joinedAt`. |
| `member_location.dart` | `MemberLocation` | `userId`, `name`, `latitude`, `longitude`, `accuracy`, `updatedAt`. |
| `sos_alert.dart` | `SosAlert` | `userId`, `name`, `latitude`, `longitude`, `batteryLevel`, `triggeredAt`, `isEscalated`. Método `copyWith()`. |
| `ws_message.dart` | `WsMessage` | `type` (enum), `payload: Map<String, dynamic>`. |
| `chat_message.dart` | `ChatMessage` | `userId`, `name`, `text`, `timestamp`. |

#### `services/`

| Archivo | Servicio | Responsabilidad |
|---|---|---|
| `auth_service.dart` | `AuthService` | Login, registro, refresh, logout, guest-login, convert-guest, `getMe()`, `validateStoredSession()`. Usa Dio con interceptor de token. |
| `event_service.dart` | `EventService` | CRUD de eventos, join/leave, búsqueda, lista de participantes, generación de códigos de invitado. |
| `group_service.dart` | `GroupService` | Crear grupo, obtener miembros, transferir admin, salir, eliminar. |
| `location_service.dart` | `LocationService` | `requestPermission()`, `startTracking(intervalSeconds)` → Stream<Position>, `getCurrentPosition()`. Usa `geolocator`. |
| `ws_client.dart` | `WsClient` | Conexión WebSocket con reconexión automática (backoff exponencial). Expone `messageStream` y `stateStream`. Métodos: `connect()`, `disconnect()`, `sendLocation()`, `sendReaction()`, `sendMessage()`. |
| `sos_service.dart` | `SosService` | `activateSos()`, `deactivateSos()`, `getActiveSos(eventId)`. |
| `notification_service.dart` | `NotificationService` | Muestra notificaciones locales para SOS recibidos usando `flutter_local_notifications`. |

#### `storage/`

| Archivo | Descripción |
|---|---|
| `secure_storage.dart` | Wrapper sobre `flutter_secure_storage`. Guarda y lee `access_token`, `refresh_token`, `user_id`. Métodos: `saveTokens()`, `getAccessToken()`, `getRefreshToken()`, `clearTokens()`. |

---

### `festisafe_app/lib/presentation/`

#### `screens/`

| Pantalla | Ruta | Descripción |
|---|---|---|
| `WelcomeScreen` | `/` | Pantalla de inicio con fondo negro y logo. Botones para ir a login, registro o acceso con código de invitado. |
| `LoginScreen` | `/login` | Formulario email+contraseña. Muestra errores del `authProvider`. Navega a `/home` al autenticarse. |
| `RegisterScreen` | `/register` | Formulario nombre, email, contraseña, confirmación, teléfono opcional. Navega a `/login` al registrarse. |
| `HomeScreen` | `/home` | Dashboard principal. Muestra el grupo actual, mapa miniatura, botón SOS, nivel de batería, y acceso rápido a las demás secciones. |
| `MapScreen` | `/map/:eventId` | Mapa en tiempo real con `flutter_map` + OpenStreetMap. Marcadores de todos los miembros del grupo. Marcadores atenuados si sin actualización >5 min. Botón de brújula hacia punto de encuentro. |
| `EventsScreen` | `/events` | Lista de eventos activos con buscador. Muestra eventos propios y disponibles. |
| `EventDetailScreen` | `/events/:eventId` | Detalle del evento: nombre, fechas, ubicación, capacidad. Botón para unirse. Si es organizador, muestra opciones de gestión y generación de código QR. |
| `GroupScreen` | `/groups/:groupId` | Vista del grupo: lista de miembros con ubicación, roles, botón para agregar/expulsar. Muestra alertas SOS activas del grupo. |
| `ProfileScreen` | `/profile` | Perfil del usuario: nombre, email, teléfono. Selector de paleta de colores. Botón de cambio de contraseña y logout. Si es invitado, muestra opción de convertir cuenta. |
| `CompassScreen` | `/compass/:userId` | Brújula que apunta hacia la ubicación de otro usuario usando `sensors_plus`. Muestra distancia estimada. |
| `QrScreen` | `/qr/:eventId` | Genera y muestra el QR del código de invitado del evento usando `qr_flutter`. Solo accesible para organizadores. |
| `OrganizerDashboardScreen` | `/organizer/:eventId` | Panel del organizador: lista de participantes, alertas SOS activas, estadísticas del evento, botones de escalado de SOS. |

#### `widgets/`

Widgets reutilizables compartidos entre pantallas:
- `SosButton` — botón de emergencia con animación de pulso. Confirma antes de activar.
- `MemberMarker` — marcador de mapa para un miembro del grupo con avatar y nombre.
- `SosAlertBanner` — banner de alerta SOS con nombre, distancia y botón de escalado.
- `BatteryIndicator` — indicador visual del nivel de batería con colores (verde/amarillo/rojo).
- `ReactionBanner` — banner temporal (3s) que muestra reacciones rápidas recibidas.
- `ChatBubble` — burbuja de mensaje del chat del grupo.
- `GroupMemberTile` — tile de miembro con avatar, nombre, rol y opciones de admin.


---

### `festisafe_app/test/properties/`

19 propiedades formales verificadas con property-based testing. Cada archivo usa `StateNotifier` fakes in-memory (extienden `Fake`) para aislar la lógica sin dependencias externas.

| Archivo | Propiedades | Descripción |
|---|---|---|
| `property_01_02_auth_test.dart` | 1-2 | Token válido → sesión activa. Logout → estado limpio. |
| `property_03_04_auth_test.dart` | 3-4 | Sesión persiste entre reinicios. Error de red → estado de error. |
| `property_05_06_gps_test.dart` | 5-6 | Throttle de ubicación (10s / 3m). Visibilidad toggle. |
| `property_07_08_group_test.dart` | 7-8 | Límite de 8 miembros por grupo. Unicidad de miembros. |
| `property_09_10_sos_test.dart` | 9-10 | SOS activa → estado correcto. SOS cancelado → limpia alertas. |
| `property_11_12_sos_test.dart` | 11-12 | SOS escalado → flag `isEscalated`. Solo un SOS activo por usuario. |
| `property_13_14_event_test.dart` | 13-14 | Evento lleno → no permite más joins. Evento expirado → no permite joins. |
| `property_15_16_ws_test.dart` | 15-16 | Reconexión WS con backoff exponencial. Mensajes inválidos → no rompen el estado. |
| `property_17_18_19_test.dart` | 17-19 | Roles de grupo correctos. Chat máx. 100 chars. Reacciones broadcast al grupo. |

---

## Infraestructura (AWS)

```
Internet
    ↓
ALB (Application Load Balancer)
    ↓
ECS Fargate (festisafe-cluster / festisafe-service)
    ↓
RDS PostgreSQL (festisafe-db, us-east-1)
```

| Recurso | Valor |
|---|---|
| Imagen ECR | `484301595509.dkr.ecr.us-east-1.amazonaws.com/festisafe:latest` |
| Secretos | `festisafe/env` en Secrets Manager |
| URL pública | `http://festisafe-alb-814303465.us-east-1.elb.amazonaws.com` |
| Docs interactivos | `http://festisafe-alb-814303465.us-east-1.elb.amazonaws.com/docs` |
| RDS endpoint | `festisafe-db.cc5io4wugzm1.us-east-1.rds.amazonaws.com` |

### `deploy/setup.sh`
Script de infraestructura inicial. Crea VPC, subnets, security groups, repositorio ECR, cluster ECS, task definition, servicio Fargate, instancia RDS PostgreSQL y ALB. Solo se ejecuta una vez.

### `deploy/deploy.sh`
Script de redeploy. Hace build de la imagen Docker, login en ECR, tag y push, y fuerza un nuevo deployment en ECS (`--force-new-deployment`). Usar después de cada cambio en el backend.

### `deploy/update-secret.sh`
Actualiza el secreto `festisafe/env` en Secrets Manager con nuevos valores de `SECRET_KEY`, `DATABASE_URL` o `DEBUG`.

### `Dockerfile`
Imagen multi-stage basada en `python:3.11-slim`. Instala dependencias, copia el código y arranca con `uvicorn app.main:app --host 0.0.0.0 --port 8000`.

---

## Seguridad

- JWT con `jti` único por token — permite revocación individual sin estado en el servidor (excepto la blacklist).
- Access token: 15 minutos. Refresh token: 7 días con rotación (el refresh usado se revoca).
- Brute-force: 3 intentos fallidos → bloqueo 3 min. 6+ intentos → forzar cambio de contraseña.
- Contraseña mínimo 12 caracteres con mayúscula, minúscula, dígito y carácter especial.
- Rate limiting por IP en endpoints sensibles (registro, login, refresh, guest-login).
- Tokens invalidados al cambiar contraseña (verificación por `iat` vs `password_changed_at`).
- Tokens revocados al hacer logout (blacklist por JTI).

---

## Migraciones

No usa Alembic. Las migraciones se aplican automáticamente en `app/core/database.py` al arrancar el contenedor:

```python
def _run_migrations():
    migrations = [
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS is_guest BOOLEAN NOT NULL DEFAULT FALSE",
        "CREATE INDEX IF NOT EXISTS ix_users_is_guest ON users (is_guest)",
    ]
```

Para agregar una migración nueva, añadir el SQL a la lista `migrations`. Cada sentencia debe usar `IF NOT EXISTS` para ser idempotente.

---

## Desarrollo local

### Backend

```bash
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt
# Configurar .env con DATABASE_URL local
uvicorn app.main:app --reload
```

### Flutter

```bash
cd festisafe_app
flutter pub get
flutter run -d emulator-5554
```

### Tests Flutter

```bash
cd festisafe_app
flutter test test/properties/ --reporter expanded
```

### Deploy

```bash
# Build y push a ECR
docker build -t festisafe-api .
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 484301595509.dkr.ecr.us-east-1.amazonaws.com
docker tag festisafe-api:latest 484301595509.dkr.ecr.us-east-1.amazonaws.com/festisafe:latest
docker push 484301595509.dkr.ecr.us-east-1.amazonaws.com/festisafe:latest

# Redeploy en ECS
aws ecs update-service --cluster festisafe-cluster --service festisafe-service --force-new-deployment
```

### Variables de entorno

Copia `.env` en la raíz del proyecto y ajusta los valores. El archivo ya incluye todas las variables con valores de ejemplo.

| Variable | Descripción | Requerida |
|---|---|---|
| `SECRET_KEY` | Clave para firmar JWT (mín. 32 chars) | Sí |
| `DATABASE_URL` | URL de conexión PostgreSQL | Sí |
| `DEBUG` | `True` en desarrollo, `False` en producción | No |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Expiración access token (default: 15) | No |
| `REFRESH_TOKEN_EXPIRE_DAYS` | Expiración refresh token (default: 7) | No |
| `SMTP_HOST` | Servidor SMTP para emails de recuperación | Para password recovery |
| `SMTP_PORT` | Puerto SMTP (default: 587) | Para password recovery |
| `SMTP_USER` | Usuario SMTP | Para password recovery |
| `SMTP_PASSWORD` | Contraseña SMTP (app password si es Gmail) | Para password recovery |
| `SMTP_FROM` | Dirección remitente del email | Para password recovery |
| `APP_DEEP_LINK_BASE` | Base del deep link en emails (ej: `festisafe://app`) | No |

---

## Password Recovery

Flujo completo implementado en la versión 2.1.0. Cubre dos caminos:

**Flujo 1 — Reset con token (usuario sin sesión):**
1. `POST /api/v1/auth/forgot-password` → genera token, envía email con enlace deep link.
2. Usuario abre el enlace → `PasswordResetScreen` con token pre-rellenado.
3. `POST /api/v1/auth/reset-password` → valida token, actualiza contraseña, revoca refresh tokens.

**Flujo 2 — Cambio obligatorio (usuario con `must_change_password=True`):**
1. `POST /api/v1/auth/login` → devuelve HTTP 403 con mensaje "Debes cambiar tu contraseña antes de continuar".
2. App redirige automáticamente a `PasswordResetScreen` en modo `changeObligatory`.
3. `POST /api/v1/auth/change-password` → verifica contraseña actual, actualiza, hace auto-login.

**Endpoints nuevos:**

| Método | Ruta | Rate limit | Descripción |
|---|---|---|---|
| POST | `/auth/forgot-password` | 3/min | Solicita recuperación. Respuesta genérica (anti-enumeración). |
| POST | `/auth/reset-password` | 10/min | Valida token y establece nueva contraseña. |
| POST | `/auth/change-password` | — | Cambio autenticado (requiere JWT). |

**Seguridad:**
- Token: 32 bytes CSPRNG, hex-encoded (64 chars). Solo el hash SHA-256 se almacena en BD.
- Expiración: 30 minutos. Un solo uso (`used_at` en lugar de DELETE).
- Comparación en tiempo constante con `hmac.compare_digest`.
- Brute-force: bloqueo de IP tras 10 intentos fallidos en 1 hora.
- Limpieza automática: scheduler diario elimina tokens con `expires_at < now - 24h`.

---

## Pruebas de conexión con el backend en AWS

El backend está desplegado en AWS ECS Fargate detrás de un ALB:

```
https://festisafe-alb-814303465.us-east-1.elb.amazonaws.com
```

### Health check rápido

```bash
curl https://festisafe-alb-814303465.us-east-1.elb.amazonaws.com/health/
# Esperado: {"status":"ok","service":"FestiSafe API","version":"2.1.0"}
```

### Script de pruebas de conexión

El archivo `test_connection_aws.py` prueba los endpoints principales contra el backend en AWS:

```bash
python test_connection_aws.py
```

Prueba: health check → registro → login → perfil autenticado → forgot-password.

### Pruebas manuales con curl

```bash
# Health
curl -s https://festisafe-alb-814303465.us-east-1.elb.amazonaws.com/health/ | python -m json.tool

# Registro
curl -s -X POST https://festisafe-alb-814303465.us-east-1.elb.amazonaws.com/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","email":"test@example.com","password":"TestPass1!secure","confirm_password":"TestPass1!secure"}' \
  | python -m json.tool

# Login
curl -s -X POST https://festisafe-alb-814303465.us-east-1.elb.amazonaws.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"TestPass1!secure"}' \
  | python -m json.tool

# Forgot password (anti-enumeración — siempre 200)
curl -s -X POST https://festisafe-alb-814303465.us-east-1.elb.amazonaws.com/api/v1/auth/forgot-password \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com"}' \
  | python -m json.tool
```

### Tests backend (locales con SQLite en memoria)

```bash
# Todos los tests de password recovery
pytest tests/test_password_recovery_service_properties.py tests/test_password_recovery_service_unit.py tests/test_email_content_properties.py tests/test_scheduler_properties.py -v

# Solo property tests
pytest tests/ -k "properties" -v

# Con cobertura
pytest tests/ --cov=app --cov-report=term-missing
```

### Tests Flutter

```bash
cd festisafe_app

# Property tests (providers + screens)
flutter test test/properties/ test/providers/ test/screens/ --reporter expanded

# Solo password recovery
flutter test test/providers/password_recovery_provider_test.dart test/screens/password_reset_screen_test.dart test/screens/password_reset_screen_property_test.dart --reporter expanded
```

---

## Casos de uso resueltos

### CU-01 — Inicio de sesión y reconocimiento de rol

**Escenario:** El usuario abre la app y quiere saber qué puede hacer según su rol.

**Solución:** Al hacer login, el backend devuelve el perfil completo con el campo `role` (`user`, `organizer` o `admin`). La app adapta la UI automáticamente:
- Chip de rol visible en el AppBar del Home.
- Solo organizadores/admins ven el botón "Crear evento" y el acceso al panel de organizador.
- Solo participantes de un evento ven "Crear grupo" y "Ver mapa".
- La ruta `/organizer/:eventId` tiene un guard que redirige a `/home` si no eres organizador.
- El botón "Unirse al evento" desaparece si ya eres participante, mostrando en su lugar un badge verde "Ya eres participante".

---

### CU-02 — Uso sin tag NFC

**Escenario:** El usuario no tiene un tag NFC pero quiere usar la app.

**Solución:** El tag NFC es solo un acceso rápido para invitados (escaneas → código de 6 dígitos → entras al evento sin cuenta). El flujo normal sin tag es:
1. Registro → Login → Buscar eventos → Unirse → Usar todas las funciones.

La app funciona completamente sin NFC.

---

### CU-03 — Registro como organizador

**Escenario:** Un nuevo usuario quiere crear eventos desde el primer momento.

**Solución:** En la pantalla de registro se agregó un selector de tipo de cuenta con dos opciones:
- **Asistente** — se une a eventos y grupos (rol `user`).
- **Organizador / Guía** — crea y gestiona eventos (rol `organizer`).

El campo `is_organizer: true` se envía al backend en `POST /auth/register`, que asigna el rol correspondiente al crear la cuenta.

---

### CU-04 — Cambio de rol de usuario a organizador

**Escenario:** Un usuario que se registró como asistente (o entró con código de invitado) ahora quiere organizar su propio evento.

**Solución:** En la pantalla de Perfil, los usuarios con rol `user` ven una tarjeta "¿Quieres organizar eventos?" con el botón "Convertirme en organizador". Al confirmarlo:
1. La app llama a `POST /users/me/become-organizer` (nuevo endpoint).
2. El backend cambia el rol a `organizer` en la base de datos.
3. La app refresca la sesión y el chip de rol en el Home se actualiza inmediatamente.

El cambio es permanente (solo un admin puede revertirlo).

---

### CU-05 — Login se queda en carga infinita

**Escenario:** El usuario presiona "Iniciar sesión" y el botón queda girando indefinidamente sin respuesta.

**Causa:** Si el backend devolvía un error que no era `DioException` (timeout, sin internet, etc.), el `AuthNotifier` quedaba en estado `AuthLoading` para siempre. Además, el `_submitting = false` se ejecutaba después del `await` pero el router ya había navegado y el widget estaba desmontado.

**Solución:**
- Se agregó `catch (_)` genérico en `login()` y `register()` del `AuthNotifier` que transiciona a `AuthError('Error de conexión...')`.
- Se reemplazó el flujo `setState` post-await por `try/finally` que garantiza el reset del flag `_submitting` incluso si el widget se desmonta.
- La navegación a `/home` la maneja el router automáticamente al detectar el cambio de estado a `AuthAuthenticated`.

---

### CU-06 — Selector de fecha de fin no se actualiza al crear evento

**Escenario:** Al crear un evento, el organizador selecciona la fecha de fin pero el botón sigue mostrando la fecha anterior.

**Causa:** El `showDatePicker` usaba `ctx` (contexto interno del `StatefulBuilder`) en lugar del `context` del widget padre. Con el diálogo abierto, ese contexto interno puede no ser válido para abrir otro diálogo encima.

**Solución:**
- Ambos pickers ahora usan el `context` correcto del widget padre.
- Los botones son de ancho completo en lugar de estar en un `Row` apretado.
- Si se cambia la fecha de inicio a después de la fecha de fin, la fecha de fin se ajusta automáticamente.
- Se muestra el año completo (`dd/mm/yyyy`) para evitar confusión.

---

### CU-07 — Error 422 al crear evento

**Escenario:** El organizador completa el formulario y presiona "Crear", pero recibe un error 422.

**Causa:** El schema `EventCreate` del backend requería el campo `expires_at` como obligatorio, pero el formulario de Flutter no lo enviaba.

**Solución:** Se hizo `expires_at` opcional en el schema. Si no se envía, el backend lo calcula automáticamente como `ends_at + 7 días`. El formulario no necesita pedirle este campo al usuario.

---

### CU-08 — Botón SOS se queda activo / no se puede desactivar

**Escenario:** El usuario activa el SOS pero al volver al mapa el botón sigue mostrando "ACTIVO" aunque ya lo desactivó, o viceversa.

**Causa:** El estado `isSosActive` del `sosProvider` vive en memoria y se pierde al navegar. Al entrar al mapa, el provider no sabía el estado real del SOS en el backend.

**Solución:** Al inicializar el `MapScreen`, se consulta `GET /sos/{eventId}/active` para sincronizar el estado real. Si el usuario tiene un SOS activo en el backend, el botón lo refleja correctamente. Además se eliminó el bloqueo que impedía activar SOS sin GPS — ahora funciona siempre, enviando coordenadas si están disponibles o usando la última ubicación conocida del backend.

---

### CU-09 — Análisis completo de gaps de UX

**Escenario:** Revisión sistemática de todos los flujos de usuario.

**Problemas encontrados y soluciones:**

- **Salir del evento:** No había botón. Agregado en `EventDetailScreen` para participantes, con confirmación.
- **Rol no visible en perfil:** `ProfileScreen` no mostraba el rol actual. Agregado chip de rol (Asistente / Organizador / Administrador) al inicio del perfil.
- **Agregar miembros al grupo:** El admin del grupo no tenía forma de agregar miembros desde la UI. Agregado botón `person_add` en el AppBar de `GroupScreen` que abre un diálogo para ingresar el ID del usuario.
- **Eliminar evento:** Agregado botón "Eliminar evento" en el panel del organizador con confirmación.
- **Datepicker del dashboard:** El diálogo de crear evento en `OrganizerDashboardScreen` tenía el mismo bug de contexto que `HomeScreen`. Corregido.

---

### CU-10 — Organizador no ve sus eventos creados / SOS no funciona

**Escenario:** El organizador crea un evento pero no aparece en su lista de inicio. Al intentar activar el SOS en el mapa, no funciona.

**Causa 1 — Eventos no visibles:** `myEventsProvider` solo consultaba `/events/my` (eventos donde el usuario es participante activo). El organizador no se unía automáticamente al evento que creaba, así que no aparecía en esa lista.

**Causa 2 — SOS falla:** El endpoint `/sos/{eventId}/activate` verifica que el usuario sea participante activo del evento. Como el organizador no estaba inscrito, el backend rechazaba la petición.

**Solución:**
- Al crear un evento, el backend ahora inscribe automáticamente al organizador como participante con rol `organizer` (usando `db.flush()` para obtener el ID antes del commit).
- `myEventsProvider` ahora combina `/events/my` + `/events/organized` eliminando duplicados. El organizador siempre ve todos sus eventos, incluso los recién creados.

---

### CU-11 — Botón SOS se queda activo al mantenerlo presionado

**Escenario:** El usuario mantiene presionado el botón SOS para desactivarlo, pero el botón no responde porque ya está en estado activo.

**Causa:** El `_onTapDown` del `SosButton` tenía la condición `if (sosState.isSosActive || _loading) return`, que bloqueaba el inicio del hold cuando el SOS ya estaba activo. Esto impedía desactivarlo con el mismo gesto de mantener presionado.

**Solución:** Se eliminó `sosState.isSosActive` de la condición de bloqueo. Ahora el hold funciona en ambos sentidos: mantener presionado activa el SOS si está inactivo, y lo desactiva si está activo. Solo `_loading` bloquea el gesto para evitar doble disparo.
