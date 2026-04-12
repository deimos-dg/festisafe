# FestiSafe

Plataforma de seguridad para festivales de música. Compuesta por una API REST/WebSocket en FastAPI, una app móvil en Flutter y un portal web de administración en Next.js.

**Backend:** `https://festisafe-production.up.railway.app`
**Portal web:** `https://festisafe-web-production.up.railway.app`

---

## Estructura del proyecto

```
festisafe/
├── app/                        # Backend (FastAPI)
│   ├── api/
│   │   ├── deps.py             # Dependencias de autenticación
│   │   └── v1/endpoints/       # Routers: auth, users, events, groups, gps, sos, ws, admin, companies, billing, intelligence, dashboard
│   ├── core/                   # Config, seguridad, WS manager, scheduler, FCM, email
│   ├── crud/                   # Queries de base de datos
│   ├── db/
│   │   └── models/             # Modelos SQLAlchemy
│   ├── schemas/                # Schemas Pydantic v2
│   └── main.py                 # Entrypoint FastAPI
├── festisafe_app/              # App móvil (Flutter)
│   └── lib/
│       ├── core/               # Router, tema, constantes
│       ├── data/               # Modelos, servicios HTTP/WS, storage
│       ├── presentation/       # Pantallas y widgets
│       └── providers/          # Estado global (Riverpod)
├── festisafe_web/              # Portal web (Next.js)
│   └── app/
│       ├── admin/              # Dashboard, empresas, billing, historial, equipo, perfil
│       └── portal/             # Mapa en vivo, folios
├── deploy/                     # Scripts de deploy AWS
├── Dockerfile
└── requirements.txt
```

---

## Backend (FastAPI)

### Tecnologías

| Componente | Tecnología |
|---|---|
| Framework | FastAPI 0.115 |
| ORM | SQLAlchemy 2.0 |
| Base de datos | PostgreSQL (Railway) |
| Autenticación | JWT HS256 (access 15 min + refresh 7 días, rotación) |
| Hashing | bcrypt + SHA-256 pre-hash |
| WebSocket | FastAPI WebSocket nativo |
| Tareas periódicas | APScheduler |
| Rate limiting | slowapi |
| Validación | Pydantic v2 |
| Servidor | Uvicorn |
| Pagos | Stripe |
| Push notifications | Firebase Admin SDK (FCM) |
| Email | SMTP (aiosmtplib) |

### Variables de entorno requeridas

```env
SECRET_KEY=<mínimo 32 caracteres>
DATABASE_URL=postgresql://user:pass@host:5432/db
DEBUG=false
ENABLE_DOCS=false
BACKEND_CORS_ORIGINS=["https://festisafe-web-production.up.railway.app"]
```

Opcionales:
```env
FIREBASE_SERVICE_ACCOUNT_JSON=<JSON del service account>
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=...
SMTP_PASSWORD=...
STRIPE_SECRET_KEY=sk_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

### Endpoints principales

#### Autenticación — `/api/v1/auth`
| Método | Ruta | Descripción |
|---|---|---|
| POST | `/register` | Registro. Rate limit 5/min. |
| POST | `/login` | Login con brute-force protection. Rate limit 10/min. |
| POST | `/refresh` | Renovar tokens (rotación). Rate limit 20/min. |
| POST | `/logout` | Revocar token (blacklist JTI). |
| POST | `/guest-login` | Canjear código OTP de 6 dígitos. |
| POST | `/convert-guest` | Convertir cuenta invitado en permanente. |
| POST | `/forgot-password` | Iniciar recuperación por email. |
| POST | `/reset-password` | Restablecer con token de un solo uso. |
| POST | `/change-password` | Cambiar contraseña (incluye flujo `must_change_password`). |

#### Usuarios — `/api/v1/users`
| Método | Ruta | Descripción |
|---|---|---|
| GET | `/me` | Perfil del usuario autenticado. |
| PATCH | `/me` | Actualizar nombre y teléfono. |
| POST | `/me/change-password` | Cambiar contraseña. |
| POST | `/me/become-organizer` | Auto-promover a organizador. |
| POST | `/me/fcm-token` | Registrar token FCM. |
| DELETE | `/me/fcm-token` | Eliminar token FCM al logout. |
| DELETE | `/me` | Eliminar cuenta (GDPR). |
| GET | `/active` | Ubicaciones activas (admin/organizer). |
| GET | `/{user_id}` | Perfil público. |
| PATCH | `/{user_id}/role` | Cambiar rol (solo admin). |

#### Eventos — `/api/v1/events`
| Método | Ruta | Descripción |
|---|---|---|
| POST | `/` | Crear evento (organizador/admin). |
| GET | `/my` | Mis eventos. |
| GET | `/search` | Buscar eventos activos. |
| GET | `/public` | Búsqueda pública sin auth. |
| GET | `/organized` | Eventos que organizo. |
| GET | `/{id}` | Detalle del evento. |
| PATCH | `/{id}` | Editar evento. |
| DELETE | `/{id}` | Eliminar evento. |
| POST | `/{id}/activate` | Activar evento. |
| POST | `/{id}/deactivate` | Desactivar evento. |
| POST | `/{id}/join` | Unirse al evento. |
| POST | `/{id}/leave` | Salir del evento. |
| GET | `/{id}/participants` | Lista de participantes. |
| POST | `/{id}/guest-code` | Generar código OTP de invitado. |

#### Grupos — `/api/v1/groups`
| Método | Ruta | Descripción |
|---|---|---|
| POST | `/` | Crear grupo. |
| GET | `/my/{event_id}` | Mi grupo en el evento. |
| GET | `/{id}` | Detalle del grupo. |
| GET | `/{id}/members` | Miembros del grupo. |
| POST | `/{id}/transfer-admin` | Transferir administración. |
| POST | `/{id}/leave` | Salir del grupo. |
| DELETE | `/{id}` | Eliminar grupo. |
| PATCH | `/{id}/meeting-point` | Establecer punto de encuentro. |
| DELETE | `/{id}/meeting-point` | Eliminar punto de encuentro. |
| GET | `/event/{event_id}/available` | Grupos disponibles en el evento. |
| POST | `/{id}/request-join` | Solicitar unirse al grupo. |
| GET | `/{id}/requests` | Ver solicitudes pendientes (admin). |
| POST | `/{id}/requests/{req_id}/accept` | Aceptar solicitud. |
| POST | `/{id}/requests/{req_id}/reject` | Rechazar solicitud. |

#### GPS — `/api/v1/gps`
| Método | Ruta | Descripción |
|---|---|---|
| POST | `/location/{event_id}` | Actualizar ubicación (fallback HTTP). Escribe en historial. |
| GET | `/location/{event_id}` | Ubicaciones del grupo/evento. |
| GET | `/company/{company_id}` | Ubicaciones de empleados de empresa. |
| GET | `/history/{user_id}` | Historial de trayectoria (últimas 24h, máx 500 puntos). |
| PATCH | `/visibility/{event_id}` | Toggle visibilidad en el mapa. |

#### SOS — `/api/v1/sos`
| Método | Ruta | Descripción |
|---|---|---|
| POST | `/{event_id}/activate` | Activar alerta SOS. Broadcast inmediato. |
| POST | `/{event_id}/deactivate` | Desactivar SOS. |
| POST | `/{event_id}/escalate/{user_id}` | Escalar SOS (solo organizador). |
| GET | `/{event_id}/active` | SOS activos en el evento. |
| GET | `/recent` | SOS activos en todo el sistema (admin). |

#### WebSocket — `/ws/location/{event_id}`

Autenticación: primer mensaje `{"type": "auth", "token": "..."}`.

Mensajes entrantes: `location`, `pong`, `reaction`, `message`.
Mensajes salientes: `connected`, `location`, `ping`, `sos`, `sos_cancelled`, `sos_escalated`, `reaction`, `message`, `group_meeting_point`, `group_join_request`, `group_join_accepted`, `group_join_rejected`, `broadcast`, `error`.

Códigos de cierre: `4001` token inválido, `4003` acceso denegado, `4008` demasiadas conexiones.

#### Empresas — `/api/v1/companies`
| Método | Ruta | Descripción |
|---|---|---|
| GET | `/` | Listar empresas activas (super admin). |
| POST | `/` | Crear empresa con fechas de contrato. |
| GET | `/history` | Empresas con contrato expirado. |
| DELETE | `/{id}` | Eliminar empresa y todos sus datos. |
| PATCH | `/{id}/status` | Activar o suspender empresa. |
| POST | `/{id}/extend` | Extender contrato por N días. |
| POST | `/{id}/manual-payment` | Registrar pago manual. |
| GET | `/{id}/folios` | Listar folios de la empresa. |
| POST | `/{id}/folios/bulk` | Generar folios masivos desde CSV. |
| GET | `/{id}/folios/export` | Exportar folios a Excel. |

#### Billing — `/api/v1/billing`
| Método | Ruta | Descripción |
|---|---|---|
| POST | `/checkout` | Crear sesión de pago Stripe. |
| POST | `/webhook` | Webhook de Stripe (sin auth JWT). |
| GET | `/transactions` | Historial de transacciones (admin). |

#### Admin — `/api/v1/admin`
| Método | Ruta | Descripción |
|---|---|---|
| GET | `/users` | Listar usuarios con filtros. |
| PATCH | `/users/{id}/activate` | Activar cuenta. |
| PATCH | `/users/{id}/deactivate` | Desactivar cuenta. |
| PATCH | `/users/{id}/unlock` | Desbloquear cuenta. |
| GET | `/events` | Listar todos los eventos. |
| GET | `/stats` | Estadísticas globales. |

#### Intelligence — `/api/v1/intelligence`
| Método | Ruta | Descripción |
|---|---|---|
| POST | `/geofences` | Crear zona de control. |
| POST | `/broadcast` | Enviar mensaje masivo a empleados. |
| GET | `/heatmap` | Datos de calor de ubicaciones. |

### Scheduler (APScheduler)

| Job | Intervalo | Descripción |
|---|---|---|
| `check_geofences` | 2 min | Detecta entradas/salidas de geofences. |
| `deactivate_expired_events` | 5 min | Desactiva eventos cuyo `expires_at` pasó. |
| `cleanup_expired_groups` | 30 min | Elimina grupos de eventos terminados. |
| `cleanup_revoked_tokens` | 1 hora | Purga blacklist de tokens expirados. |
| `cleanup_expired_reset_tokens` | 24 horas | Purga tokens de recuperación expirados. |
| `notify_expiring_contracts` | 24 horas | Alerta WS de contratos próximos a vencer. |
| `purge_location_history` | 7 días | Elimina historial de ubicaciones >30 días. |

### Seguridad

- Brute-force: 3 intentos → 3 min lock, 6+ → `must_change_password`
- JWT con JTI único por token (revocación individual)
- Token rotation en refresh
- Tokens invalidados al cambiar contraseña (`iat` vs `password_changed_at`)
- Rate limiting por IP en endpoints sensibles
- Anti-Slowloris (timeout 30s)
- Max body size 1 MB
- CORS restringido a dominios de producción
- Empresa suspendida bloquea login de sus usuarios

---

## App Móvil (Flutter)

### Tecnologías

| Componente | Tecnología |
|---|---|
| Framework | Flutter 3.29+ / Dart 3.3+ |
| Estado | Riverpod 2.x (StateNotifier) |
| Navegación | go_router |
| HTTP | Dio 5.x con interceptor JWT |
| WebSocket | web_socket_channel (backoff exponencial) |
| Mapas | flutter_map + CartoDB Dark tiles |
| GPS | geolocator (adaptativo por batería) |
| BLE | flutter_blue_plus (fallback offline) |
| Notificaciones | flutter_local_notifications + FCM |
| QR | mobile_scanner + qr_flutter |
| Batería | battery_plus |
| Brújula | sensors_plus |
| Storage | flutter_secure_storage + shared_preferences |

### Pantallas

| Pantalla | Ruta | Descripción |
|---|---|---|
| `OnboardingScreen` | `/onboarding` | 4 páginas. Se muestra una sola vez al primer arranque o registro. |
| `WelcomeScreen` | `/` | Entrada: login, registro, código invitado. |
| `LoginScreen` | `/login` | Email + contraseña. |
| `RegisterScreen` | `/register` | Registro con tipo de cuenta (asistente/organizador/staff con folio). |
| `HomeScreen` | `/home` | Dashboard: mis eventos, acceso rápido. |
| `MapScreen` | `/map/:eventId` | Mapa cyber-dark en tiempo real. Marcadores de grupo, SOS radar, punto de encuentro del evento y del grupo, toggle de visibilidad, BLE fallback. |
| `ChatScreen` | `/map/:eventId/chat` | Chat fullscreen. También embebido en GroupScreen. |
| `GroupScreen` | `/groups/:groupId` | Miembros + Chat. Solicitudes de unión para el admin. |
| `CompassScreen` | `/compass/:userId` | Brújula táctica con dial, distancia y animación de pulso. |
| `EventsScreen` | `/events` | Búsqueda de eventos. |
| `EventDetailScreen` | `/events/:eventId` | Detalle, unirse/salir. |
| `EventGroupsScreen` | `/event-groups/:eventId` | Grupos disponibles con solicitud de unión. |
| `OrganizerDashboardScreen` | `/organizer/:eventId` | Panel organizador: SOS, participantes, punto de encuentro, broadcast masivo. |
| `QrScreen` | `/qr/:eventId` | Código OTP con QR y opción de compartir. |
| `ParticipantsScreen` | `/participants/:eventId` | Lista de participantes con toggle grupo/todos. |
| `ProfileScreen` | `/profile` | Avatar (12 iconos + foto), tema, contraseña, logout, eliminar cuenta. |
| `AdminScreen` | `/admin` | Panel admin: stats, usuarios, eventos. |
| `JoinScreen` | `/join/:code` | Deep link para canjear código de invitado. |
| `ForgotPasswordScreen` | `/forgot-password` | Solicitar recuperación. |
| `PasswordResetScreen` | `/reset-password` | Restablecer con token. |

### Providers

| Provider | Estado |
|---|---|
| `authProvider` | `AuthState` (Initial/Loading/Authenticated/Guest/Unauthenticated/Error/MustChangePassword) |
| `locationProvider` | `LocationState` (position, isTracking, isVisible) |
| `memberLocationsProvider` | `Map<userId, MemberLocation>` con caché offline |
| `wsProvider` | `WsConnectionState` (disconnected/connecting/connected/reconnecting) |
| `sosProvider` | `SosState` (isSosActive, activeAlerts) |
| `groupProvider` | `GroupState` (group, isLoading, error) |
| `chatProvider` | `List<ChatMessage>` (máx 500, en memoria) |
| `bleProvider` | `BleState` (isActive, nearbyDevices) |
| `batteryProvider` | `int` (nivel %, cada 30s) |
| `connectivityProvider` | `ConnectivityStatus` (online/offline) |
| `themeProvider` | `ThemeState` (mode, paletteIndex) |
| `passwordRecoveryProvider` | `PasswordRecoveryState` |

### Flujo BLE (fallback offline)

Cuando el WS se desconecta por más de 15 segundos, se activa Bluetooth Low Energy para mantener la detección de proximidad del grupo. Al reconectar el WS, BLE se detiene automáticamente.

---

## Portal Web (Next.js)

Ver `festisafe_web/README.md` para documentación detallada.

### Funcionalidades principales

- Dashboard con métricas en tiempo real y alertas de contratos próximos a vencer
- Gestión de empresas: alta, baja, suspensión, extensión de contrato, pagos manuales
- Detalle de empresa: folios con búsqueda/filtros, historial de transacciones
- Facturación con Stripe: checkout, webhook, historial paginado
- Historial de empresas con contrato expirado y tasa de cobertura
- Mapa en vivo con Leaflet: empleados en tiempo real, SOS, geofences, broadcast
- Gestión de folios: carga CSV con preview, exportar Excel
- Equipo interno: crear admins/viewers, activar/desactivar
- Protección de rutas por rol (super admin vs admin)

---

## Deploy en Railway

### Backend (`festisafe`)

Variables requeridas en Railway:
```
SECRET_KEY=<32+ chars>
DATABASE_URL=${{Postgres.DATABASE_URL}}
DEBUG=false
ENABLE_DOCS=false
BACKEND_CORS_ORIGINS=["https://festisafe-web-production.up.railway.app"]
ACCESS_TOKEN_EXPIRE_MINUTES=15
```

Start command: `uvicorn app.main:app --host 0.0.0.0 --port 8000`

### Portal Web (`festisafe-web`)

Variables:
```
NEXT_PUBLIC_API_URL=https://festisafe-production.up.railway.app
```

Start command:
```
cp -r .next/static .next/standalone/.next/static && cp -r public .next/standalone/public && HOSTNAME=0.0.0.0 node .next/standalone/server.js
```

Puerto: 8080. Root directory: `/festisafe_web`.

---

## Desarrollo local

### Backend
```bash
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env       # Configurar variables
uvicorn app.main:app --reload
```

### App móvil
```bash
cd festisafe_app
flutter pub get
flutter run
```

### Portal web
```bash
cd festisafe_web
npm install
npm run dev
```
