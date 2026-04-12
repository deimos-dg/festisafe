'use client';

import { useState, useEffect } from 'react';
import { fetchWithAuth } from '@/lib/api';

interface Company {
  id: string;
  name: string;
  primary_email: string;
  status: string;
  total_folios_contracted: number;
  used_folios_count: number;
  contract_start: string;
  contract_end: string;
}

const PAGE_SIZE = 15;

export default function HistoryPage() {
  const [companies, setCompanies] = useState<Company[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);

  useEffect(() => {
    fetchWithAuth('/companies/history')
      .then(setCompanies)
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => { setPage(1); }, [search]);

  const filtered = companies.filter(c =>
    !search ||
    c.name.toLowerCase().includes(search.toLowerCase()) ||
    c.primary_email.toLowerCase().includes(search.toLowerCase())
  );

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const totalFoliosUsed = companies.reduce((acc, c) => acc + c.used_folios_count, 0);
  const totalFoliosContracted = companies.reduce((acc, c) => acc + c.total_folios_contracted, 0);

  return (
    <div className="relative min-h-screen p-8 lg:p-12">
      <header className="mb-10">
        <h1 className="text-4xl font-black text-white tracking-tight flex items-center gap-3 italic uppercase">
          <span className="w-2 h-8 bg-slate-500 rounded-full inline-block" />
          Historial <span className="text-slate-400 not-italic font-medium text-xl ml-2 tracking-widest">Eventos Completados</span>
        </h1>
        <p className="text-slate-500 text-xs font-black uppercase tracking-[0.3em] ml-5 mt-1">
          Empresas cuyo contrato de servicio ya finalizó
        </p>
      </header>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-4 mb-10">
        <div className="glass-card p-5 rounded-2xl border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Eventos Completados</p>
          <p className="text-2xl font-black text-white">{companies.length}</p>
        </div>
        <div className="glass-card p-5 rounded-2xl border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Folios Utilizados</p>
          <p className="text-2xl font-black text-indigo-400">{totalFoliosUsed}</p>
        </div>
        <div className="glass-card p-5 rounded-2xl border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Tasa de Uso</p>
          <p className="text-2xl font-black text-emerald-400">
            {totalFoliosContracted > 0
              ? `${Math.round((totalFoliosUsed / totalFoliosContracted) * 100)}%`
              : '—'}
          </p>
        </div>
      </div>

      {/* Búsqueda */}
      <div className="mb-6">
        <input type="text" placeholder="Buscar empresa..."
          value={search} onChange={e => setSearch(e.target.value)}
          className="w-full max-w-sm bg-white/[0.05] border border-white/10 rounded-xl px-4 py-2 text-xs text-white outline-none focus:border-indigo-500 transition-all" />
      </div>

      {loading ? (
        <div className="flex justify-center items-center h-48">
          <div className="w-10 h-10 border-4 border-slate-500/20 border-t-slate-500 rounded-full animate-spin" />
        </div>
      ) : companies.length === 0 ? (
        <div className="glass-card rounded-[2.5rem] p-16 text-center border-white/5 bg-white/5">
          <p className="text-4xl mb-3">📁</p>
          <p className="text-slate-500 text-xs font-black uppercase tracking-widest">Sin eventos completados aún</p>
          <p className="text-slate-600 text-[11px] mt-2">Aquí aparecerán las empresas cuyo contrato haya finalizado</p>
        </div>
      ) : (
        <div className="glass-card rounded-[2.5rem] overflow-hidden border-white/5">
          <table className="w-full text-left">
            <thead>
              <tr className="bg-white/[0.02] border-b border-white/5">
                <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Empresa</th>
                <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Inicio</th>
                <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Fin</th>
                <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Duración</th>
                <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Folios usados</th>
                <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Cobertura</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/[0.02]">
              {paginated.map(c => {
                const days = Math.ceil(
                  (new Date(c.contract_end).getTime() - new Date(c.contract_start).getTime()) / 86400000
                );
                const pct = c.total_folios_contracted > 0
                  ? Math.round((c.used_folios_count / c.total_folios_contracted) * 100)
                  : 0;
                return (
                  <tr key={c.id} className="hover:bg-white/[0.03] transition-colors">
                    <td className="px-8 py-5">
                      <div className="flex items-center gap-3">
                        <div className="w-9 h-9 rounded-xl bg-slate-700/40 border border-slate-600/30 flex items-center justify-center font-black text-slate-400 text-sm">
                          {c.name[0]}
                        </div>
                        <div>
                          <p className="text-sm font-bold text-white">{c.name}</p>
                          <p className="text-[11px] text-slate-500">{c.primary_email}</p>
                        </div>
                      </div>
                    </td>
                    <td className="px-8 py-5 text-xs text-slate-400">
                      {new Date(c.contract_start).toLocaleDateString('es-MX')}
                    </td>
                    <td className="px-8 py-5 text-xs text-slate-400">
                      {new Date(c.contract_end).toLocaleDateString('es-MX')}
                    </td>
                    <td className="px-8 py-5 text-xs font-bold text-white">{days}d</td>
                    <td className="px-8 py-5">
                      <div className="flex items-center gap-2">
                        <div className="w-16 h-1.5 bg-slate-800 rounded-full overflow-hidden">
                          <div className={`h-full rounded-full ${pct >= 80 ? 'bg-emerald-500' : pct >= 50 ? 'bg-amber-500' : 'bg-red-500'}`}
                            style={{ width: `${pct}%` }} />
                        </div>
                        <span className="text-xs font-black text-white">{c.used_folios_count}/{c.total_folios_contracted}</span>
                      </div>
                    </td>
                    <td className="px-8 py-5">
                      <span className={`text-sm font-black ${pct >= 80 ? 'text-emerald-400' : pct >= 50 ? 'text-amber-400' : 'text-red-400'}`}>
                        {pct}%
                      </span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Paginación */}
      {!loading && filtered.length > PAGE_SIZE && (
        <div className="flex items-center justify-between mt-4">
          <p className="text-[10px] text-slate-500 font-bold uppercase tracking-widest">
            {filtered.length} resultados · Página {page} de {totalPages}
          </p>
          <div className="flex gap-2">
            <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}
              className="px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-wider bg-white/5 text-slate-400 border border-white/10 hover:bg-white/10 disabled:opacity-30 disabled:cursor-not-allowed transition-all">
              ← Anterior
            </button>
            <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}
              className="px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-wider bg-white/5 text-slate-400 border border-white/10 hover:bg-white/10 disabled:opacity-30 disabled:cursor-not-allowed transition-all">
              Siguiente →
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
