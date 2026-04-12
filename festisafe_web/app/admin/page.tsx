'use client';

import Link from 'next/link';
import { useState, useEffect } from 'react';
import { adminApi } from '@/lib/api';

export default function OwnerAdminDashboard() {
  const [stats, setStats] = useState<any>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const loadStats = async () => {
      try {
        const data = await adminApi.getStats();
        setStats(data);
      } catch (error) {
        console.error("Error loading stats:", error);
      } finally {
        setIsLoading(false);
      }
    };
    loadStats();
  }, []);

  const adminStats = [
    { label: 'Usuarios Totales', val: stats?.total_users || '0', delta: 'Global', color: 'text-emerald-400' },
    { label: 'Empresas Activas', val: stats?.total_companies || '0', delta: 'B2B', color: 'text-indigo-400' },
    { label: 'Eventos Activos', val: stats?.active_events || '0', delta: 'Live', color: 'text-orange-400' },
    { label: 'Alertas SOS', val: stats?.active_sos || '0', delta: 'Crítico', color: 'text-red-400' },
  ];

  const quickActions = [
    { name: 'Gestión de Empresas', desc: 'Altas, bajas y folios iniciales', href: '/admin/companies', icon: '🏢' },
    { name: 'Facturación', desc: 'Pagos, transacciones y contratos', href: '/admin/billing', icon: '💳' },
    { name: 'Soporte B2B', desc: 'Tickets y atención a clientes', href: '#', icon: '📩' },
    { name: 'Reportes Globales', desc: 'Exportación masiva de datos', href: '#', icon: '📊' },
  ];

  return (
    <div className="relative min-h-screen p-8 lg:p-12">

      {/* Header Central */}
      <div className="flex flex-col items-center text-center mb-16 space-y-4">
        <div className="w-20 h-20 bg-indigo-600/20 border border-indigo-500/30 rounded-[2.5rem] flex items-center justify-center text-4xl mb-2 shadow-[0_0_30px_rgba(99,102,241,0.2)]">
          🛡️
        </div>
        <div>
          <h1 className="text-5xl font-black text-white italic uppercase tracking-tighter">
            Owner <span className="text-indigo-500">Console</span>
          </h1>
          <p className="text-slate-500 text-[10px] font-black uppercase tracking-[0.5em] mt-2">
            Centro de Mando Global FestiSafe
          </p>
        </div>
      </div>

      {/* Grid de Métricas Tácticas */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-16">
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

      {/* Acciones Rápidas (Cards Gigantes) */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
        {quickActions.map((action, i) => (
          <Link href={action.href} key={i}>
            <div className="glass-card p-10 rounded-[3rem] border-white/5 bg-white/5 hover:bg-white/10 hover:border-indigo-500/30 transition-all group flex items-center gap-8 relative overflow-hidden">
               {/* Decorativo de Fondo */}
               <div className="absolute -bottom-10 -right-10 text-9xl opacity-[0.02] group-hover:opacity-[0.05] transition-opacity">
                 {action.icon}
               </div>

               <div className="w-20 h-20 bg-indigo-500/10 rounded-3xl flex items-center justify-center text-4xl group-hover:scale-110 transition-transform">
                 {action.icon}
               </div>

               <div className="flex-1">
                 <h3 className="text-2xl font-black text-white uppercase italic mb-1 group-hover:text-indigo-400 transition-colors">
                   {action.name}
                 </h3>
                 <p className="text-sm font-medium text-slate-500">
                   {action.desc}
                 </p>
               </div>

               <div className="w-12 h-12 rounded-full border border-white/10 flex items-center justify-center text-slate-500 group-hover:bg-indigo-500 group-hover:text-white transition-all">
                 →
               </div>
            </div>
          </Link>
        ))}
      </div>

      {/* Footer / Status Log */}
      <div className="mt-16 flex justify-between items-center text-[10px] font-black text-slate-700 uppercase tracking-widest px-8">
        <p>© 2026 FestiSafe Cloud Architecture</p>
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 bg-emerald-500 rounded-full" />
          <p>Railway Node: USA-EAST-1 (Active)</p>
        </div>
      </div>

    </div>
  );
}
