'use client';

import { useState, useEffect, useCallback } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { fetchWithAuth } from '@/lib/api';

interface Company {
  id: string;
  name: string;
  primary_email: string;
  tax_id: string | null;
  status: 'active' | 'suspended' | 'pending';
  total_folios_contracted: number;
  used_folios_count: number;
  contract_start: string;
  contract_end: string | null;
  created_at: string;
}

interface Folio {
  id: string;
  code: string;
  employee_name: string | null;
  employee_role: string | null;
  employee_phone: string | null;
  is_used: boolean;
  used_at: string | null;
  created_at: string;
}

interface Transaction {
  id: string;
  amount: number;
  type: string;
  status: string;
  date: string;
  description: string;
  stripe_session_id: string | null;
}

const STATUS_STYLE: Record<string, string> = {
  active:    'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
  suspended: 'bg-red-500/10 text-red-400 border-red-500/20',
  pending:   'bg-amber-500/10 text-amber-400 border-amber-500/20',
};

export default function CompanyDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();

  const [company, setCompany] = useState<Company | null>(null);
  const [folios, setFolios] = useState<Folio[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'folios' | 'transactions'>('folios');
  const [search, setSearch] = useState('');
  const [filterStatus, setFilterStatus] = useState<'all' | 'used' | 'available'>('all');
  const [actionLoading, setActionLoading] = useState('');

  const loadAll = useCallback(async () => {
    try {
      const [companiesData, foliosData, txData] = await Promise.all([
        fetchWithAuth('/companies/'),
        fetchWithAuth(`/companies/${id}/folios`).catch(() => []),
        fetchWithAuth('/billing/transactions').catch(() => []),
      ]);
      const found = (companiesData as Company[]).find(c => c.id === id);
      if (!found) { router.replace('/admin/companies'); return; }
      setCompany(found);
      setFolios(Array.isArray(foliosData) ? foliosData : []);
      // Filtrar transacciones de esta empresa por nombre
      const companyTx = (txData as Transaction[]).filter(
        (tx: Transaction & { company?: string }) => tx.company === found.name
      );
      setTransactions(companyTx);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  }, [id, router]);

  useEffect(() => { loadAll(); }, [loadAll]);

  async function toggleStatus() {
    if (!company) return;
    const newStatus = company.status === 'active' ? 'suspended' : 'active';
    setActionLoading('status');
    try {
      await fetchWithAuth(`/companies/${id}/status?status=${newStatus}`, { method: 'PATCH' });
      loadAll();
    } catch { alert('Error al cambiar estado'); }
    finally { setActionLoading(''); }
  }

  function handleExport() {
    const apiBase = process.env.NEXT_PUBLIC_API_URL || 'https://festisafe-production.up.railway.app';
    window.open(`${apiBase}/api/v1/companies/${id}/folios/export`, '_blank');
  }

  const filteredFolios = folios.filter(f => {
    const matchSearch = !search ||
      f.code.toLowerCase().includes(search.toLowerCase()) ||
      (f.employee_name || '').toLowerCase().includes(search.toLowerCase()) ||
      (f.employee_role || '').toLowerCase().includes(search.toLowerCase());
    const matchStatus =
      filterStatus === 'all' ||
      (filterStatus === 'used' && f.is_used) ||
      (filterStatus === 'available' && !f.is_used);
    return matchSearch && matchStatus;
  });

  const daysLeft = company?.contract_end
    ? Math.ceil((new Date(company.contract_end).getTime() - Date.now()) / 86400000)
    : null;

  if (loading) {
    return (
      <div className="flex justify-center items-center min-h-screen">
        <div className="w-12 h-12 border-4 border-indigo-500/20 border-t-indigo-500 rounded-full animate-spin" />
      </div>
    );
  }

  if (!company) return null;

  const pct = Math.min((company.used_folios_count / Math.max(company.total_folios_contracted, 1)) * 100, 100);

  return (
    <div className="relative min-h-screen p-8 lg:p-12">
      {/* Header */}
      <header className="flex items-start gap-4 mb-10">
        <button onClick={() => router.back()}
          className="mt-1 p-2 rounded-xl bg-white/5 hover:bg-white/10 text-slate-400 hover:text-white transition-all">
          ←
        </button>
        <div className="flex-1">
          <div className="flex items-center gap-4 flex-wrap">
            <div className="w-14 h-14 rounded-2xl bg-indigo-600/20 border border-indigo-500/30 flex items-center justify-center font-black text-indigo-400 text-2xl">
              {company.name[0]}
            </div>
            <div>
              <h1 className="text-3xl font-black text-white italic uppercase tracking-tight">{company.name}</h1>
              <p className="text-slate-500 text-sm">{company.primary_email}</p>
            </div>
            <span className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-wider border ${STATUS_STYLE[company.status]}`}>
              <span className={`w-1.5 h-1.5 rounded-full ${company.status === 'active' ? 'bg-emerald-400 animate-pulse' : 'bg-current'}`} />
              {company.status}
            </span>
          </div>
        </div>
        <div className="flex gap-3 flex-shrink-0">
          <button onClick={toggleStatus} disabled={actionLoading === 'status'}
            className={`px-5 py-2.5 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all border ${
              company.status === 'active'
                ? 'bg-red-500/10 text-red-400 border-red-500/20 hover:bg-red-500/20'
                : 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20 hover:bg-emerald-500/20'
            }`}>
            {actionLoading === 'status' ? '...' : company.status === 'active' ? 'Suspender' : 'Activar'}
          </button>
          <button onClick={handleExport}
            className="px-5 py-2.5 rounded-xl text-[10px] font-black uppercase tracking-wider bg-white/5 text-slate-300 border border-white/10 hover:bg-white/10 transition-all">
            📊 Exportar
          </button>
        </div>
      </header>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-10">
        <div className="glass-card p-5 rounded-2xl border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Folios</p>
          <p className="text-2xl font-black text-white">{company.used_folios_count}/{company.total_folios_contracted}</p>
          <div className="mt-2 h-1.5 bg-slate-800 rounded-full overflow-hidden">
            <div className={`h-full rounded-full ${pct > 90 ? 'bg-red-500' : pct > 70 ? 'bg-amber-500' : 'bg-indigo-500'}`}
              style={{ width: `${pct}%` }} />
          </div>
        </div>
        <div className="glass-card p-5 rounded-2xl border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Contrato inicio</p>
          <p className="text-sm font-black text-white">{new Date(company.contract_start).toLocaleDateString('es-MX')}</p>
        </div>
        <div className="glass-card p-5 rounded-2xl border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Contrato fin</p>
          {daysLeft !== null ? (
            <p className={`text-sm font-black ${daysLeft > 7 ? 'text-emerald-400' : daysLeft > 0 ? 'text-amber-400' : 'text-red-400'}`}>
              {new Date(company.contract_end!).toLocaleDateString('es-MX')}
              <span className="text-[10px] ml-1">({daysLeft > 0 ? `${daysLeft}d` : 'Expirado'})</span>
            </p>
          ) : (
            <p className="text-sm text-slate-600">Sin fecha fin</p>
          )}
        </div>
        <div className="glass-card p-5 rounded-2xl border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Transacciones</p>
          <p className="text-2xl font-black text-indigo-400">{transactions.filter(t => t.status === 'completed').length}</p>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 mb-6">
        {(['folios', 'transactions'] as const).map(tab => (
          <button key={tab} onClick={() => setActiveTab(tab)}
            className={`px-5 py-2.5 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all border ${
              activeTab === tab ? 'bg-indigo-600 text-white border-indigo-500' : 'bg-white/5 text-slate-400 border-white/10 hover:bg-white/10'
            }`}>
            {tab === 'folios' ? `📋 Folios (${folios.length})` : `💳 Pagos (${transactions.length})`}
          </button>
        ))}
      </div>

      {/* Tab: Folios */}
      {activeTab === 'folios' && (
        <>
          <div className="flex flex-wrap gap-3 mb-4">
            <input type="text" placeholder="Buscar código, nombre o rol..."
              value={search} onChange={e => setSearch(e.target.value)}
              className="flex-1 min-w-[200px] bg-white/[0.05] border border-white/10 rounded-xl px-4 py-2 text-xs text-white outline-none focus:border-indigo-500 transition-all" />
            {(['all', 'available', 'used'] as const).map(f => (
              <button key={f} onClick={() => setFilterStatus(f)}
                className={`px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all border ${
                  filterStatus === f ? 'bg-indigo-600 text-white border-indigo-500' : 'bg-white/5 text-slate-400 border-white/10 hover:bg-white/10'
                }`}>
                {f === 'all' ? 'Todos' : f === 'available' ? 'Disponibles' : 'Canjeados'}
              </button>
            ))}
          </div>
          <div className="glass-card rounded-[2rem] overflow-hidden border-white/5">
            <table className="w-full text-left">
              <thead>
                <tr className="bg-white/[0.02] border-b border-white/5">
                  {['Código', 'Empleado', 'Rol', 'Teléfono', 'Estado', 'Fecha'].map(h => (
                    <th key={h} className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-white/[0.02]">
                {filteredFolios.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="px-6 py-12 text-center text-slate-600 text-xs font-black uppercase tracking-widest">
                      {folios.length === 0 ? 'Sin folios generados' : 'Sin resultados'}
                    </td>
                  </tr>
                ) : filteredFolios.map(f => (
                  <tr key={f.id} className="hover:bg-white/[0.03] transition-colors">
                    <td className="px-6 py-4">
                      <span className="text-sm font-mono font-black text-indigo-300">{f.code}</span>
                    </td>
                    <td className="px-6 py-4 text-xs font-bold text-white">{f.employee_name || '—'}</td>
                    <td className="px-6 py-4">
                      <span className="text-[10px] font-black text-slate-400 border border-slate-800 px-2 py-1 rounded-lg bg-slate-900/50">
                        {f.employee_role || '—'}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-xs text-slate-500">{f.employee_phone || '—'}</td>
                    <td className="px-6 py-4">
                      <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-xl text-[10px] font-black uppercase tracking-wider border ${
                        f.is_used ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20' : 'bg-indigo-500/10 text-indigo-400 border-indigo-500/20'
                      }`}>
                        <span className={`w-1.5 h-1.5 rounded-full ${f.is_used ? 'bg-emerald-400' : 'bg-indigo-400 animate-pulse'}`} />
                        {f.is_used ? 'Canjeado' : 'Disponible'}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-[10px] text-slate-500">
                      {f.is_used && f.used_at
                        ? new Date(f.used_at).toLocaleDateString('es-MX')
                        : new Date(f.created_at).toLocaleDateString('es-MX')}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      {/* Tab: Transacciones */}
      {activeTab === 'transactions' && (
        <div className="glass-card rounded-[2rem] overflow-hidden border-white/5">
          <table className="w-full text-left">
            <thead>
              <tr className="bg-white/[0.02] border-b border-white/5">
                {['Descripción', 'Monto', 'Tipo', 'Estado', 'Fecha'].map(h => (
                  <th key={h} className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-white/[0.02]">
              {transactions.length === 0 ? (
                <tr>
                  <td colSpan={5} className="px-6 py-12 text-center text-slate-600 text-xs font-black uppercase tracking-widest">
                    Sin transacciones registradas
                  </td>
                </tr>
              ) : transactions.map(tx => (
                <tr key={tx.id} className="hover:bg-white/[0.03] transition-colors">
                  <td className="px-6 py-4 text-xs text-slate-400 max-w-[200px] truncate">{tx.description}</td>
                  <td className="px-6 py-4 text-sm font-black text-white">
                    ${tx.amount.toLocaleString('es-MX', { minimumFractionDigits: 2 })} MXN
                  </td>
                  <td className="px-6 py-4 text-xs text-slate-400">{tx.type}</td>
                  <td className="px-6 py-4">
                    <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-xl text-[10px] font-black uppercase tracking-wider border ${
                      tx.status === 'completed' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20' :
                      tx.status === 'pending' ? 'bg-amber-500/10 text-amber-400 border-amber-500/20' :
                      'bg-red-500/10 text-red-400 border-red-500/20'
                    }`}>
                      {tx.status === 'completed' ? 'Completado' : tx.status === 'pending' ? 'Pendiente' : 'Fallido'}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-xs text-slate-500">
                    {new Date(tx.date).toLocaleDateString('es-MX')}
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
