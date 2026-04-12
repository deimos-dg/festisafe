/**
 * Las páginas de /portal usan el mismo layout del admin (sidebar + nav)
 * excepto /portal/map que es fullscreen y lo maneja internamente.
 */
import AdminLayout from '@/app/admin/layout';

export default function PortalLayout({ children }: { children: React.ReactNode }) {
  return <AdminLayout>{children}</AdminLayout>;
}
