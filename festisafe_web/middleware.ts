import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

// Rutas que requieren estar autenticado
const PROTECTED_PREFIXES = ['/admin', '/portal'];

// Rutas que requieren rol super admin (admin en el backend)
const SUPER_ADMIN_ONLY = ['/admin/billing', '/admin/users', '/admin/history'];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const isProtected = PROTECTED_PREFIXES.some(p => pathname.startsWith(p));
  if (!isProtected) return NextResponse.next();

  const isAuthed = request.cookies.has('fs_authed');
  if (!isAuthed) {
    return NextResponse.redirect(new URL('/', request.url));
  }

  // Verificar rutas de super admin
  const isSuperAdminRoute = SUPER_ADMIN_ONLY.some(p => pathname.startsWith(p));
  if (isSuperAdminRoute) {
    const role = request.cookies.get('fs_role')?.value;
    if (role !== 'admin') {
      // Redirigir al dashboard sin exponer que la ruta existe
      return NextResponse.redirect(new URL('/admin', request.url));
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/admin/:path*', '/portal/:path*'],
};
