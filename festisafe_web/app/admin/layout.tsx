'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { clearToken, isSuperAdmin, getUser } from '@/lib/api';

const NAV_ALL = [
  { href: '/admin',           label: 'Dashboard',   icon: '🛡️' },
  { href: '/admin/companies', label: 'Empresas',     icon: '🏢' },
  { href: '/portal/map',      label: 'Mapa en Vivo', icon: '🗺️' },
  { href: '/portal/folios',   label: 'Folios',       icon: '📋' },
];

const NAV_SUPER_ADMIN = [
  { href: '/admin/billing',   label: 'Facturación',  icon: '💳' },
  { href: '/admin/users',     label: 'Mi Equipo',    icon: '👥' },
  { href: '/admin/history',   label: 'Historial',    icon: '📁' },
];

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const superAdmin = isSuperAdmin();
  const user = getUser();

  const navItems = superAdmin ? [...NAV_ALL, ...NAV_SUPER_ADMIN] : NAV_ALL;

  function handleLogout() {
    clearToken();
    router.push('/');
  }

  return (
    <div className="flex min-h-screen">
      {/* Sidebar */}
      <aside className="fixed left-0 top-0 bottom-0 w-64 z-40 flex flex-col
                        bg-[#030712]/80 backdrop-blur-2xl border-r border-white/5">
        {/* Logo */}
        <div className="flex items-center gap-3 px-6 py-8 border-b border-white/5">
          <div className="w-10 h-10 bg-indigo-600 rounded-2xl flex items-center justify-center shadow-lg shadow-indigo-500/30 flex-shrink-0">
            <span className="text-white font-black text-sm">FS</span>
          </div>
          <div>
            <p className="text-white font-black text-sm tracking-tight">FestiSafe</p>
            <p className="text-[9px] text-slate-500 uppercase tracking-widest font-bold">
              {superAdmin ? 'Super Admin' : 'Admin'}
            </p>
          </div>
        </div>

        {/* Nav */}
        <nav className="flex-1 px-4 py-6 space-y-1 overflow-y-auto">
          {navItems.map(item => {
            const active = pathname === item.href ||
              (item.href !== '/admin' && pathname.startsWith(item.href));
            return (
              <Link key={item.href} href={item.href}
                className={`flex items-center gap-3 px-4 py-3 rounded-2xl text-xs font-black uppercase tracking-wider transition-all ${
                  active
                    ? 'bg-indigo-600/20 text-indigo-400 border border-indigo-500/30'
                    : 'text-slate-500 hover:text-white hover:bg-white/5'
                }`}>
                <span className="text-base">{item.icon}</span>
                {item.label}
              </Link>
            );
          })}
        </nav>

        {/* User + Logout */}
        <div className="px-4 py-6 border-t border-white/5 space-y-3">
          <Link href="/admin/profile"
            className="flex items-center gap-3 px-4 py-3 rounded-2xl bg-white/[0.03] border border-white/5 hover:bg-white/[0.06] transition-all group">
            <div className="w-8 h-8 rounded-xl bg-indigo-600/20 border border-indigo-500/20 flex items-center justify-center font-black text-indigo-400 text-sm flex-shrink-0">
              {((user?.name as string) || 'A')[0]?.toUpperCase()}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-[10px] text-slate-500 uppercase tracking-widest font-bold">Sesión activa</p>
              <p className="text-xs text-white font-bold truncate">
                {(user?.email as string) || '—'}
              </p>
            </div>
            <span className="text-slate-600 group-hover:text-slate-400 text-xs">⚙</span>
          </Link>
          <button onClick={handleLogout}
            className="w-full flex items-center gap-3 px-4 py-3 rounded-2xl text-xs font-black uppercase tracking-wider text-red-400 hover:bg-red-500/10 transition-all">
            <span>🚪</span> Cerrar Sesión
          </button>
        </div>
      </aside>

      {/* Content */}
      <main className="flex-1 ml-64 relative z-10 min-h-screen">
        {children}
      </main>
    </div>
  );
}
