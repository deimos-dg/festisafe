/**
 * El mapa es fullscreen — no usa el sidebar del admin.
 * Este layout vacío sobreescribe el portal/layout.tsx para esta ruta.
 */
export default function MapLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}
