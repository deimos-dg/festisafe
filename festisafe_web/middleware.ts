import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

const PROTECTED_PREFIXES = ['/admin', '/portal'];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const isProtected = PROTECTED_PREFIXES.some((prefix) =>
    pathname.startsWith(prefix)
  );

  if (!isProtected) return NextResponse.next();

  // El token se guarda en sessionStorage (client-side), no en cookies,
  // por lo que el middleware no puede leerlo directamente.
  // Usamos una cookie ligera 'fs_authed' que el cliente establece al hacer login
  // y que el middleware puede verificar sin exponer el JWT.
  const isAuthed = request.cookies.has('fs_authed');

  if (!isAuthed) {
    const loginUrl = new URL('/', request.url);
    return NextResponse.redirect(loginUrl);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/admin/:path*', '/portal/:path*'],
};
