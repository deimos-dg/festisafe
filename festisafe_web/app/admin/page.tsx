'use client';

import Link from 'next/link';
import { useState, useEffect } from 'react';
import { adminApi, fetchWithAuth, isSuperAdmin } from '@/lib/api';

interface ExpiringCompany {
  id: string;
  name: string;
  contract_end: string;
}

export default function OwnerAdminDashboard() {
  const [stats, setStats] = useState<Record<string, number> | null>(null);
  const [expiring, setExpiring] = useState<ExpiringCompany[]>([]);
  const superAdmin = isSuperAdmin();

  useEffect(() => {
    adminApi.getStats().then(setStats).catch(console.error);
    // Cargar empresas próximas a vencer (solo super admin)
    if (isSuperAdmin()) {
      fetchWithAuth('/companies/')
        .then((data: ExpiringCompany[]) => {
          const now = Date.now();
          const soon = data.filter((c: ExpiringCompany) => {
            if (!c.contract_end) return false;
            const diff = new Date(c.contract_end).getTime() - now;
            return diff > 0 && diff <= 7 * 86400000; // 7 días
          });
          setExpiring(soon);
        })
        .catch(console.error);
    }
  }, []);

  const adminStats = [
    { label: 'Usuarios Totales', val: stats?.total_users ?? '—', delta: 'Global', color: 'text-emerald-400' },
    { label: 'Empresas Activas', val: stats?.total_companies ?? '—', delta: 'B2B', color: 'text-indigo-400' },
    { label: 'Eventos Activos', val: stats?.active_events ?? '—', delta: 'Live', color: 'text-orange-400' },
    { label: 'Alertas SOS', val: stats?.active_sos ?? '—', delta: 'Crítico', color: 'text-red-400' },
  ];

  const allActions = [
    { name: 'Gestión de Empresas', desc: 'Altas, bajas y folios iniciales', href: '/admin/companies', icon: '🏢', superOnly: false },
    { name: 'Mapa en Vivo', desc: 'Monitoreo de personal en tiempo real', href: '/portal/map', icon: '🗺️', superOnly: false },
    { name: 'Facturación', desc: 'Pagos, transacciones y contratos', href: '/admin/billing', icon: '💳', superOnly: true },
    { name: 'Mi Equipo', desc: 'Gestión de usuarios internos', href: '/admin/users', icon: '👥', superOnly: true },
    { name: 'Folios', desc: 'Credenciales y personal operativo', href: '/portal/folios', icon: '📋', superOnly: false },
  ];

  const visibleActions = allActions.filter(a => !a.superOnly || superAdmin);

  return (
    <div className="relative min-h-screen p-8 lg:p-12">

      {/* Banner contratos próximos a vencer */}
      {expiring.length > 0 && (
        <div className="mb-8 bg-amber-500/10 border border-amber-500/30 rounded-2xl p-4">
          <div className="flex items-center gap-3 mb-3">
            <span className="text-lg">⚠️</span>
            <p className="text-xs font-black text-amber-400 uppercase tracking-widest">
              {expiring.length} contrato{expiring.length > 1 ? 's' : ''} próximo{expiring.length > 1 ? 's' : ''} a vencer
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            {expiring.map(c => {
              const days = Math.ceil((new Date(c.contract_end).getTime() - Date.now()) / 86400000);
              return (
                <Link key={c.id} href="/admin/companies"
                  className="flex items-center gap-2 px-3 py-1.5 bg-amber-500/10 border border-amber-500/20 rounded-xl hover:bg-amber-500/20 transition-all">
                  <span className="text-xs font-bold text-white">{c.name}</span>
                  <span className="text-[10px] font-black text-amber-400">{days}d</span>
                </Link>
              );
            })}
          </div>
        </div>
      )}

      <div className="flex flex-col items-center text-center mb-12 space-y-4">
        <div className="w-20 h-20 bg-indigo-600/20 border border-indigo-500/30 rounded-[2.5rem] flex items-center justify-center text-4xl mb-2 shadow-[0_0_30px_rgba(99,102,241,0.2)]">
          🛡️
        </div>
        <div>
          <h1 className="text-5xl font-black text-white italic uppercase tracking-tighter">
            {superAdmin ? 'Owner' : 'Admin'} <span className="text-indigo-500">Console</span>
          </h1>
          <p className="text-slate-500 text-[10px] font-black uppercase tracking-[0.5em] mt-2">
            Centro de Mando Global FestiSafe
          </p>
        </div>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-6 mb-12">
        {adminStats.map((stat, i) => (
          <div key={i} className="glass-card p-8 rounded-[2.5rem] border-white/5 bg-white/5 relative group overflow-hidden">
            <div className="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity text-2xl">⚡</div>
            <p className="text-[10px] font-black text-slate-500 uppercase tracking-[0.2em] mb-2">{stat.label}</p>
            <div className="flex items-baseline gap-3">
              <p className={`text-4xl font-black ${stat.color}`}>{stat.val}</p>
              <span className="text-[10px] font-bold text-slate-600">{stat.delta}</span>
            </div>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {visibleActions.map((action, i) => (
          <Link href={action.href} key={i}>
            <div className="glass-card p-8 rounded-[2.5rem] border-white/5 bg-white/5 hover:bg-white/10 hover:border-indigo-500/30 transition-all group flex items-center gap-6 relative overflow-hidden">
              <div className="absolute -bottom-8 -right-8 text-8xl opacity-[0.02] group-hover:opacity-[0.05] transition-opacity">
                {action.icon}
              </div>
              <div className="w-16 h-16 bg-indigo-500/10 rounded-3xl flex items-center justify-center text-3xl group-hover:scale-110 transition-transform flex-shrink-0">
                {action.icon}
              </div>
              <div className="flex-1">
                <h3 className="text-xl font-black text-white uppercase italic mb-1 group-hover:text-indigo-400 transition-colors">
                  {action.name}
                </h3>
                <p className="text-sm font-medium text-slate-500">{action.desc}</p>
              </div>
              <div className="w-10 h-10 rounded-full border border-white/10 flex items-center justify-center text-slate-500 group-hover:bg-indigo-500 group-hover:text-white transition-all flex-shrink-0">
                →
              </div>
            </div>
          </Link>
        ))}
      </div>

      <div className="mt-12 flex justify-between items-center text-[10px] font-black text-slate-700 uppercase tracking-widest px-8">
        <p>© 2026 FestiSafe Cloud Architecture</p>
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 bg-emerald-500 rounded-full" />
          <p>Railway · Online</p>
        </div>
      </div>
    </div>
  );
}
