'use client';

import { useState, useEffect, useCallback } from 'react';
import { fetchWithAuth } from '@/lib/api';

interface Transaction {
  id: string;
  company: string;
  amount: number;
  type: string;
  status: 'pending' | 'completed' | 'failed' | 'refunded';
  date: string;
  description: string;
  stripe_session_id: string | null;
}

const STATUS_STYLES: Record<string, string> = {
  completed: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
  pending:   'bg-amber-500/10 text-amber-400 border-amber-500/20',
  failed:    'bg-red-500/10 text-red-400 border-red-500/20',
  refunded:  'bg-slate-500/10 text-slate-400 border-slate-500/20',
};

const STATUS_LABELS: Record<string, string> = {
  completed: 'Completado',
  pending:   'Pendiente',
  failed:    'Fallido',
  refunded:  'Reembolsado',
};

const PAGE_SIZE = 20;

export default function BillingPage() {
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<string>('all');
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');

  const loadTransactions = useCallback(async () => {
    setLoading(true);
    try {
      const data = await fetchWithAuth('/billing/transactions');
      setTransactions(Array.isArray(data) ? data : []);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadTransactions(); }, [loadTransactions]);

  // Reset page when filter/search changes
  useEffect(() => { setPage(1); }, [filter, search]);

  const filtered = transactions.filter(t => {
    const matchFilter = filter === 'all' || t.status === filter;
    const matchSearch = !search ||
      t.company.toLowerCase().includes(search.toLowerCase()) ||
      t.description.toLowerCase().includes(search.toLowerCase());
    return matchFilter && matchSearch;
  });

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const totalRevenue = transactions
    .filter(t => t.status === 'completed')
    .reduce((acc, t) => acc + t.amount, 0);
  const pending = transactions.filter(t => t.status === 'pending').length;

  return (
    <div className="relative min-h-screen p-8 lg:p-12">
      <header className="flex flex-col md:flex-row justify-between items-start md:items-center mb-10 gap-6">
        <div className="space-y-1">
          <h1 className="text-4xl font-black text-white tracking-tight flex items-center gap-3 italic uppercase">
            <span className="w-2 h-8 bg-indigo-500 rounded-full inline-block" />
            Facturación <span className="text-indigo-400 not-italic font-medium text-xl ml-2 tracking-widest">Revenue Center</span>
          </h1>
          <p className="text-slate-500 text-xs font-black uppercase tracking-[0.3em] ml-5">Historial de Pagos y Transacciones</p>
        </div>
        <button onClick={loadTransactions}
          className="px-6 py-3 bg-white/5 hover:bg-white/10 border border-white/10 text-slate-300 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">
          ↻ Actualizar
        </button>
      </header>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-5 mb-10">
        <div className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Ingresos Totales</p>
          <p className="text-2xl font-black text-emerald-400">
            ${totalRevenue.toLocaleString('es-MX', { minimumFractionDigits: 2 })} MXN
          </p>
        </div>
        <div className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Transacciones</p>
          <p className="text-2xl font-black text-white">{transactions.length}</p>
        </div>
        <div className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Pendientes</p>
          <p className={`text-2xl font-black ${pending > 0 ? 'text-amber-400' : 'text-slate-500'}`}>{pending}</p>
        </div>
      </div>

      {/* Filtros + búsqueda */}
      <div className="flex flex-wrap gap-3 mb-6">
        <input type="text" placeholder="Buscar empresa o descripción..."
          value={search} onChange={e => setSearch(e.target.value)}
          className="flex-1 min-w-[200px] bg-white/[0.05] border border-white/10 rounded-xl px-4 py-2 text-xs text-white outline-none focus:border-indigo-500 transition-all" />
        {['all', 'completed', 'pending', 'failed'].map(f => (
          <button key={f} onClick={() => setFilter(f)}
            className={`px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all border ${
              filter === f ? 'bg-indigo-600 text-white border-indigo-500' : 'bg-white/5 text-slate-400 border-white/10 hover:bg-white/10'
            }`}>
            {f === 'all' ? 'Todos' : STATUS_LABELS[f]}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center items-center h-48">
          <div className="w-10 h-10 border-4 border-indigo-500/20 border-t-indigo-500 rounded-full animate-spin" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="glass-card rounded-[2.5rem] p-16 text-center border-white/5 bg-white/5">
          <p className="text-4xl mb-3">💳</p>
          <p className="text-slate-500 text-xs font-black uppercase tracking-widest">Sin transacciones</p>
        </div>
      ) : (
        <>
          <div className="glass-card rounded-[2rem] overflow-hidden border-white/5 mb-4">
            <table className="w-full text-left">
              <thead>
                <tr className="bg-white/[0.02] border-b border-white/5">
                  <th className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">Empresa</th>
                  <th className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">Descripción</th>
                  <th className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">Monto</th>
                  <th className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">Fecha</th>
                  <th className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">Estado</th>
                  <th className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">Ref.</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/[0.02]">
                {paginated.map(tx => (
                  <tr key={tx.id} className="hover:bg-white/[0.03] transition-colors">
                    <td className="px-6 py-4 text-sm font-bold text-white">{tx.company}</td>
                    <td className="px-6 py-4 text-xs text-slate-400 max-w-[180px] truncate">{tx.description}</td>
                    <td className="px-6 py-4 text-sm font-black text-white">
                      ${tx.amount.toLocaleString('es-MX', { minimumFractionDigits: 2 })}
                    </td>
                    <td className="px-6 py-4 text-xs text-slate-400">
                      {new Date(tx.date).toLocaleDateString('es-MX', { day: '2-digit', month: 'short', year: 'numeric' })}
                    </td>
                    <td className="px-6 py-4">
                      <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-xl text-[10px] font-black uppercase tracking-wider border ${STATUS_STYLES[tx.status] || ''}`}>
                        <span className={`w-1.5 h-1.5 rounded-full ${tx.status === 'completed' ? 'bg-emerald-400 animate-pulse' : tx.status === 'pending' ? 'bg-amber-400' : 'bg-red-400'}`} />
                        {STATUS_LABELS[tx.status] || tx.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-[10px] text-slate-600 font-mono truncate max-w-[100px]">
                      {tx.stripe_session_id || '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Paginación */}
          <div className="flex items-center justify-between">
            <p className="text-[10px] text-slate-500 font-bold uppercase tracking-widest">
              {filtered.length} resultados · Página {page} de {totalPages}
            </p>
            <div className="flex gap-2">
              <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}
                className="px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-wider bg-white/5 text-slate-400 border border-white/10 hover:bg-white/10 disabled:opacity-30 disabled:cursor-not-allowed transition-all">
                ← Anterior
              </button>
              {Array.from({ length: Math.min(5, totalPages) }, (_, i) => {
                const p = Math.max(1, Math.min(page - 2, totalPages - 4)) + i;
                return (
                  <button key={p} onClick={() => setPage(p)}
                    className={`w-9 h-9 rounded-xl text-[10px] font-black transition-all border ${
                      p === page ? 'bg-indigo-600 text-white border-indigo-500' : 'bg-white/5 text-slate-400 border-white/10 hover:bg-white/10'
                    }`}>
                    {p}
                  </button>
                );
              })}
              <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}
                className="px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-wider bg-white/5 text-slate-400 border border-white/10 hover:bg-white/10 disabled:opacity-30 disabled:cursor-not-allowed transition-all">
                Siguiente →
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
