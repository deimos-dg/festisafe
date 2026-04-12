# FestiSafe Web — Panel de Administración

Portal web de administración para el sistema FestiSafe. Construido con Next.js 16 y desplegado en Railway.

**URL de producción:** `https://festisafe-web-production.up.railway.app`

---

## Stack

| Componente | Tecnología |
|---|---|
| Framework | Next.js 16.2 (App Router, Turbopack) |
| Lenguaje | TypeScript 5 |
| Estilos | Tailwind CSS 4 |
| Mapas | Leaflet + react-leaflet |
| Deploy | Railway (standalone server) |

---

## Estructura

```
festisafe_web/
├── app/
│   ├── page.tsx                    # Login
│   ├── change-password/            # Cambio obligatorio de contraseña
│   ├── admin/
│   │   ├── layout.tsx              # Sidebar de navegación con control de roles
│   │   ├── page.tsx                # Dashboard con métricas y alertas
│   │   ├── companies/
│   │   │   ├── page.tsx            # Lista de empresas (vista lista/grid)
│   │   │   └── [id]/page.tsx       # Detalle de empresa: folios y transacciones
│   │   ├── billing/page.tsx        # Historial de pagos con paginación
│   │   ├── history/page.tsx        # Empresas con contrato finalizado
│   │   ├── users/page.tsx          # Gestión de equipo interno (solo super admin)
│   │   └── profile/page.tsx        # Perfil y cambio de contraseña del admin
│   └── portal/
│       ├── layout.tsx              # Reutiliza sidebar del admin
│       ├── map/
│       │   ├── layout.tsx          # Layout vacío (mapa es fullscreen)
│       │   └── page.tsx            # Mapa en vivo con Leaflet
│       └── folios/page.tsx         # Gestión de folios por empresa con CSV
├── lib/
│   └── api.ts                      # Cliente HTTP, auth helpers, token management
└── middleware.ts                   # Protección de rutas por autenticación y rol
```

---

## Roles y accesos

| Sección | Super Admin | Admin |
|---|---|---|
| Dashboard | ✅ | ✅ |
| Empresas | ✅ | ✅ |
| Detalle de empresa | ✅ | ✅ |
| Mapa en vivo | ✅ | ✅ |
| Folios | ✅ | ✅ |
| Facturación | ✅ | ❌ |
| Historial | ✅ | ❌ |
| Mi Equipo | ✅ | ❌ |
| Perfil | ✅ | ✅ |

---

## Variables de entorno

```env
NEXT_PUBLIC_API_URL=https://festisafe-production.up.railway.app
```

---

## Desarrollo local

```bash
cd festisafe_web
npm install
npm run dev
```

Abre `http://localhost:3000`.

---

## Deploy en Railway

El servicio usa el modo `standalone` de Next.js.

**Start command:**
```
cp -r .next/static .next/standalone/.next/static && cp -r public .next/standalone/public && HOSTNAME=0.0.0.0 node .next/standalone/server.js
```

**Puerto:** 8080 (Railway lo asigna automáticamente).

---

## Autenticación

El token JWT se guarda en `sessionStorage` (no `localStorage`) para mayor seguridad ante XSS. Una cookie ligera `fs_authed` permite al middleware de Next.js verificar autenticación en SSR sin exponer el JWT. El rol se persiste en `fs_role` para proteger rutas de super admin.

---

## Funcionalidades principales

- **Empresas** — alta, baja, suspensión, extensión de contrato, registro de pagos manuales (efectivo/transferencia/Stripe), vista lista y cuadrícula
- **Detalle de empresa** — folios con búsqueda y filtros, historial de transacciones
- **Facturación** — historial paginado con búsqueda, filtros por estado, stats de ingresos
- **Historial** — empresas con contrato expirado, tasa de cobertura de folios
- **Mapa en vivo** — Leaflet con tiles oscuros CartoDB, marcadores de empleados en tiempo real, alertas SOS, log de geofences, broadcast masivo
- **Folios** — carga de CSV con parsing en cliente, preview antes de confirmar, exportar Excel
- **Mi Equipo** — crear empleados internos con rol Admin o Viewer, activar/desactivar
- **Perfil** — actualizar datos, cambiar contraseña con re-login automático
- **Dashboard** — banner de contratos próximos a vencer (≤7 días)
