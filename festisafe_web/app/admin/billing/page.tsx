'use client';

import { useState, useEffect } from 'react';
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

export default function BillingPage() {
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<string>('all');

  useEffect(() => { loadTransactions(); }, []);

  async function loadTransactions() {
    try {
      const data = await fetchWithAuth('/billing/transactions');
      setTransactions(data);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  }

  const filtered = filter === 'all'
    ? transactions
    : transactions.filter(t => t.status === filter);

  const totalRevenue = transactions
    .filter(t => t.status === 'completed')
    .reduce((acc, t) => acc + t.amount, 0);

  const pending = transactions.filter(t => t.status === 'pending').length;

  return (
    <div className="relative min-h-screen p-8 lg:p-12">
      <header className="flex flex-col md:flex-row justify-between items-start md:items-center mb-12 gap-6">
        <div className="space-y-1">
          <h1 className="text-4xl font-black text-white tracking-tight flex items-center gap-3 italic uppercase">
            <span className="w-2 h-8 bg-indigo-500 rounded-full inline-block" />
            Facturación <span className="text-indigo-400 not-italic font-medium text-xl ml-2 tracking-widest">Revenue Center</span>
          </h1>
          <p className="text-slate-500 text-xs font-black uppercase tracking-[0.3em] ml-5">
            Historial de Pagos y Transacciones
          </p>
        </div>
        <button onClick={loadTransactions}
          className="px-6 py-3 bg-white/5 hover:bg-white/10 border border-white/10 text-slate-300 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">
          ↻ Actualizar
        </button>
      </header>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
        <div className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Ingresos Totales</p>
          <p className="text-3xl font-black text-emerald-400">
            ${totalRevenue.toLocaleString('es-MX', { minimumFractionDigits: 2 })} MXN
          </p>
        </div>
        <div className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Transacciones</p>
          <p className="text-3xl font-black text-white">{transactions.length}</p>
        </div>
        <div className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Pendientes</p>
          <p className={`text-3xl font-black ${pending > 0 ? 'text-amber-400' : 'text-slate-500'}`}>{pending}</p>
        </div>
      </div>

      {/* Filtros */}
      <div className="flex gap-3 mb-8 flex-wrap">
        {['all', 'completed', 'pending', 'failed'].map(f => (
          <button key={f} onClick={() => setFilter(f)}
            className={`px-5 py-2 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all border ${
              filter === f
                ? 'bg-indigo-600 text-white border-indigo-500'
                : 'bg-white/5 text-slate-400 border-white/10 hover:bg-white/10'
            }`}>
            {f === 'all' ? 'Todos' : STATUS_LABELS[f]}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center items-center h-64">
          <div className="w-12 h-12 border-4 border-indigo-500/20 border-t-indigo-500 rounded-full animate-spin" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="glass-card rounded-[2.5rem] p-16 text-center border-white/5 bg-white/5">
          <p className="text-4xl mb-4">💳</p>
          <p className="text-slate-500 text-xs font-black uppercase tracking-widest">Sin transacciones</p>
        </div>
      ) : (
        <div className="glass-card rounded-[2.5rem] overflow-hidden border-white/5">
          <table className="w-full text-left">
            <thead>
              <tr className="bg-white/[0.02] border-b border-white/5">
                <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Empresa</th>
                <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Descripción</th>
                <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Monto</th>
                <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Fecha</th>
                <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Estado</th>
                <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Referencia</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/[0.02]">
              {filtered.map(tx => (
                <tr key={tx.id} className="hover:bg-white/[0.03] transition-colors">
                  <td className="px-8 py-5 text-sm font-bold text-white">{tx.company}</td>
                  <td className="px-8 py-5 text-xs text-slate-400 max-w-[200px] truncate">{tx.description}</td>
                  <td className="px-8 py-5 text-sm font-black text-white">
                    ${tx.amount.toLocaleString('es-MX', { minimumFractionDigits: 2 })}
                  </td>
                  <td className="px-8 py-5 text-xs text-slate-400">
                    {new Date(tx.date).toLocaleDateString('es-MX', { day: '2-digit', month: 'short', year: 'numeric' })}
                  </td>
                  <td className="px-8 py-5">
                    <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-xl text-[10px] font-black uppercase tracking-wider border ${STATUS_STYLES[tx.status] || ''}`}>
                      <span className={`w-1.5 h-1.5 rounded-full ${tx.status === 'completed' ? 'bg-emerald-400 animate-pulse' : tx.status === 'pending' ? 'bg-amber-400' : 'bg-red-400'}`} />
                      {STATUS_LABELS[tx.status] || tx.status}
                    </span>
                  </td>
                  <td className="px-8 py-5 text-[10px] text-slate-600 font-mono truncate max-w-[120px]">
                    {tx.stripe_session_id || '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
