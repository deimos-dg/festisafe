'use client';

import { useState, useEffect } from 'react';
import { adminApi, fetchWithAuth } from '@/lib/api';

interface Company {
  id: string;
  name: string;
  primary_email: string;
  status: 'active' | 'suspended' | 'pending';
  total_folios_contracted: number;
  used_folios_count: number;
  contract_start: string;
  contract_end: string | null;
}

type ViewMode = 'list' | 'grid';

const STATUS_STYLE = {
  active:    'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
  suspended: 'bg-red-500/10 text-red-400 border-red-500/20',
  pending:   'bg-amber-500/10 text-amber-400 border-amber-500/20',
};

function daysLeft(company: Company): number | null {
  if (!company.contract_end) return null;
  return Math.ceil((new Date(company.contract_end).getTime() - Date.now()) / 86400000);
}

function DaysChip({ company }: { company: Company }) {
  const d = daysLeft(company);
  if (d === null) return <span className="text-xs text-slate-600">Sin fecha fin</span>;
  if (d > 7)  return <span className="text-xs font-black text-emerald-400">{d}d restantes</span>;
  if (d > 0)  return <span className="text-xs font-black text-amber-400">⚠️ {d}d restantes</span>;
  return <span className="text-xs font-black text-red-400">Expirado</span>;
}

export default function AdminCompaniesPage() {
  const [companies, setCompanies] = useState<Company[]>([]);
  const [payments, setPayments] = useState<Record<string, boolean>>({});
  const [loading, setLoading] = useState(true);
  const [view, setView] = useState<ViewMode>('list');
  const [showModal, setShowModal] = useState(false);
  const [showPaymentModal, setShowPaymentModal] = useState<Company | null>(null);
  const [showExtendModal, setShowExtendModal] = useState<Company | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<Company | null>(null);
  const [actionLoading, setActionLoading] = useState('');
  const [formData, setFormData] = useState({
    name: '', primary_email: '', total_folios_contracted: 50,
    contract_start: '', contract_end: '',
  });
  const [paymentForm, setPaymentForm] = useState({ amount: '', method: 'transfer', description: '' });
  const [extendDays, setExtendDays] = useState(30);

  useEffect(() => { loadAll(); }, []);

  async function loadAll() {
    try {
      const data = await adminApi.getCompanies();
      setCompanies(data);
      const txData = await fetchWithAuth('/billing/transactions').catch(() => []);
      const paidMap: Record<string, boolean> = {};
      for (const tx of txData) {
        if (tx.status === 'completed') {
          const match = data.find((c: Company) => c.name === tx.company);
          if (match) paidMap[match.id] = true;
        }
      }
      setPayments(paidMap);
    } catch (e) { console.error(e); }
    finally { setLoading(false); }
  }

  async function handleCreate(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setActionLoading('create');
    try {
      await adminApi.createCompany({
        name: formData.name,
        primary_email: formData.primary_email,
        total_folios_contracted: formData.total_folios_contracted,
        contract_start: formData.contract_start || undefined,
        contract_end: formData.contract_end || undefined,
      });
      setShowModal(false);
      setFormData({ name: '', primary_email: '', total_folios_contracted: 50, contract_start: '', contract_end: '' });
      loadAll();
    } catch { alert('Error al crear la empresa'); }
    finally { setActionLoading(''); }
  }

  async function toggleStatus(company: Company) {
    const newStatus = company.status === 'active' ? 'suspended' : 'active';
    setActionLoading(company.id + '_status');
    try {
      await fetchWithAuth(`/companies/${company.id}/status?status=${newStatus}`, { method: 'PATCH' });
      loadAll();
    } catch { alert('Error al cambiar estado'); }
    finally { setActionLoading(''); }
  }

  async function handleDelete() {
    if (!confirmDelete) return;
    setActionLoading('delete_' + confirmDelete.id);
    try {
      await fetchWithAuth(`/companies/${confirmDelete.id}`, { method: 'DELETE' });
      setConfirmDelete(null);
      loadAll();
    } catch { alert('Error al eliminar empresa'); }
    finally { setActionLoading(''); }
  }

  async function handleManualPayment(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!showPaymentModal) return;
    setActionLoading('payment');
    try {
      await fetchWithAuth(
        `/companies/${showPaymentModal.id}/manual-payment?amount=${paymentForm.amount}&payment_method=${paymentForm.method}&description=${encodeURIComponent(paymentForm.description || 'Pago manual')}`,
        { method: 'POST' }
      );
      setShowPaymentModal(null);
      setPaymentForm({ amount: '', method: 'transfer', description: '' });
      loadAll();
    } catch { alert('Error al registrar pago'); }
    finally { setActionLoading(''); }
  }

  async function handleExtend(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!showExtendModal) return;
    setActionLoading('extend');
    try {
      await fetchWithAuth(`/companies/${showExtendModal.id}/extend?days=${extendDays}`, { method: 'POST' });
      setShowExtendModal(null);
      loadAll();
    } catch (err: unknown) {
      alert(err instanceof Error ? err.message : 'Error al extender contrato');
    } finally { setActionLoading(''); }
  }

  return (
    <div className="relative min-h-screen p-8 lg:p-12">
      {/* Header */}
      <header className="flex flex-col md:flex-row justify-between items-start md:items-center mb-10 gap-6">
        <div className="space-y-1">
          <h1 className="text-4xl font-black text-white tracking-tight flex items-center gap-3 italic uppercase">
            <span className="w-2 h-8 bg-indigo-500 rounded-full inline-block" />
            Empresas <span className="text-indigo-400 not-italic font-medium text-xl ml-2 tracking-widest">Fleet Control</span>
          </h1>
          <p className="text-slate-500 text-xs font-black uppercase tracking-[0.3em] ml-5">Gestión Global de Clientes y Contratos</p>
        </div>
        <div className="flex items-center gap-3">
          {/* Toggle vista */}
          <div className="flex bg-white/5 border border-white/10 rounded-xl p-1 gap-1">
            {(['list', 'grid'] as ViewMode[]).map(v => (
              <button key={v} onClick={() => setView(v)}
                className={`px-3 py-1.5 rounded-lg text-[10px] font-black uppercase tracking-wider transition-all ${
                  view === v ? 'bg-indigo-600 text-white' : 'text-slate-500 hover:text-white'
                }`}>
                {v === 'list' ? '☰ Lista' : '⊞ Grid'}
              </button>
            ))}
          </div>
          <button onClick={() => setShowModal(true)} className="premium-button flex items-center gap-2 px-6">
            <span>+</span> Nueva Empresa
          </button>
        </div>
      </header>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-4 mb-10">
        <div className="glass-card p-5 rounded-2xl border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Total</p>
          <p className="text-2xl font-black text-white">{companies.length}</p>
        </div>
        <div className="glass-card p-5 rounded-2xl border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Activas</p>
          <p className="text-2xl font-black text-emerald-400">{companies.filter(c => c.status === 'active').length}</p>
        </div>
        <div className="glass-card p-5 rounded-2xl border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Suspendidas</p>
          <p className="text-2xl font-black text-red-400">{companies.filter(c => c.status === 'suspended').length}</p>
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center items-center h-48">
          <div className="w-10 h-10 border-4 border-indigo-500/20 border-t-indigo-500 rounded-full animate-spin" />
        </div>
      ) : view === 'list' ? (
        <ListaView companies={companies} payments={payments} actionLoading={actionLoading}
          onToggle={toggleStatus} onPayment={setShowPaymentModal}
          onExtend={setShowExtendModal} onDelete={setConfirmDelete} />
      ) : (
        <GridView companies={companies} payments={payments} actionLoading={actionLoading}
          onToggle={toggleStatus} onPayment={setShowPaymentModal}
          onExtend={setShowExtendModal} onDelete={setConfirmDelete} />
      )}

      {/* ── Modal: Nueva empresa ── */}
      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-6 backdrop-blur-md bg-black/50">
          <div className="glass-card rounded-[2.5rem] p-8 max-w-md w-full border-white/10 shadow-[0_0_60px_rgba(0,0,0,0.6)]">
            <h2 className="text-xl font-black text-white mb-6 italic uppercase">Nueva Empresa</h2>
            <form onSubmit={handleCreate} className="space-y-4">
              <div className="space-y-1">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Nombre Comercial</label>
                <input type="text" required className="premium-input" placeholder="Ej. Security Global SA"
                  value={formData.name} onChange={e => setFormData({...formData, name: e.target.value})} />
              </div>
              <div className="space-y-1">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Email Operativo</label>
                <input type="email" required className="premium-input" placeholder="contact@company.com"
                  value={formData.primary_email} onChange={e => setFormData({...formData, primary_email: e.target.value})} />
              </div>
              <div className="space-y-1">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Folios Contratados</label>
                <input type="number" required min="1" className="premium-input"
                  value={formData.total_folios_contracted}
                  onChange={e => setFormData({...formData, total_folios_contracted: parseInt(e.target.value)})} />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Inicio del contrato</label>
                  <input type="date" className="premium-input"
                    value={formData.contract_start}
                    onChange={e => setFormData({...formData, contract_start: e.target.value})} />
                </div>
                <div className="space-y-1">
                  <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Fin del contrato</label>
                  <input type="date" className="premium-input"
                    value={formData.contract_end}
                    onChange={e => setFormData({...formData, contract_end: e.target.value})} />
                </div>
              </div>
              {formData.contract_start && formData.contract_end && (
                <p className="text-[10px] text-indigo-400 ml-3">
                  Duración: {Math.ceil((new Date(formData.contract_end).getTime() - new Date(formData.contract_start).getTime()) / 86400000)} días
                </p>
              )}
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setShowModal(false)}
                  className="flex-1 py-3 bg-white/5 hover:bg-white/10 text-slate-400 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">
                  Cancelar
                </button>
                <button type="submit" disabled={actionLoading === 'create'} className="flex-1 premium-button">
                  {actionLoading === 'create' ? '...' : 'CREAR'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ── Modal: Pago manual ── */}
      {showPaymentModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-6 backdrop-blur-md bg-black/50">
          <div className="glass-card rounded-[2.5rem] p-8 max-w-md w-full border-white/10">
            <h2 className="text-xl font-black text-white mb-1 italic uppercase">Registrar Pago</h2>
            <p className="text-slate-500 text-xs mb-6">{showPaymentModal.name}</p>
            <form onSubmit={handleManualPayment} className="space-y-4">
              <div className="space-y-1">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Monto (MXN)</label>
                <input type="number" required min="1" step="0.01" className="premium-input" placeholder="500.00"
                  value={paymentForm.amount} onChange={e => setPaymentForm({...paymentForm, amount: e.target.value})} />
              </div>
              <div className="space-y-1">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Método</label>
                <select className="premium-input" value={paymentForm.method}
                  onChange={e => setPaymentForm({...paymentForm, method: e.target.value})}>
                  <option value="transfer">Transferencia bancaria</option>
                  <option value="cash">Efectivo</option>
                  <option value="stripe">Stripe (manual)</option>
                </select>
              </div>
              <div className="space-y-1">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Descripción</label>
                <input type="text" className="premium-input" placeholder="Ej. Pago evento 15 mayo"
                  value={paymentForm.description} onChange={e => setPaymentForm({...paymentForm, description: e.target.value})} />
              </div>
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setShowPaymentModal(null)}
                  className="flex-1 py-3 bg-white/5 hover:bg-white/10 text-slate-400 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">Cancelar</button>
                <button type="submit" disabled={actionLoading === 'payment'} className="flex-1 premium-button">
                  {actionLoading === 'payment' ? '...' : 'REGISTRAR'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ── Modal: Extender contrato ── */}
      {showExtendModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-6 backdrop-blur-md bg-black/50">
          <div className="glass-card rounded-[2.5rem] p-8 max-w-sm w-full border-white/10">
            <h2 className="text-xl font-black text-white mb-1 italic uppercase">Extender Contrato</h2>
            <p className="text-slate-500 text-xs mb-2">{showExtendModal.name}</p>
            {showExtendModal.contract_end && (
              <p className="text-xs text-slate-400 mb-5">
                Vence: <span className="text-white font-bold">{new Date(showExtendModal.contract_end).toLocaleDateString('es-MX')}</span>
              </p>
            )}
            <form onSubmit={handleExtend} className="space-y-4">
              <div className="space-y-1">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Días a extender</label>
                <input type="number" required min="1" max="3650" className="premium-input"
                  value={extendDays} onChange={e => setExtendDays(parseInt(e.target.value))} />
                <p className="text-[10px] text-indigo-400 ml-3">
                  Nueva fecha: {(() => {
                    const b = showExtendModal.contract_end ? new Date(showExtendModal.contract_end) : new Date();
                    b.setDate(b.getDate() + extendDays);
                    return b.toLocaleDateString('es-MX');
                  })()}
                </p>
              </div>
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setShowExtendModal(null)}
                  className="flex-1 py-3 bg-white/5 hover:bg-white/10 text-slate-400 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">Cancelar</button>
                <button type="submit" disabled={actionLoading === 'extend'} className="flex-1 premium-button">
                  {actionLoading === 'extend' ? '...' : `+${extendDays} DÍAS`}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ── Modal: Confirmar eliminación ── */}
      {confirmDelete && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-6 backdrop-blur-md bg-black/60">
          <div className="glass-card rounded-[2.5rem] p-8 max-w-sm w-full border-red-500/20 bg-red-500/5">
            <div className="text-center mb-6">
              <p className="text-3xl mb-3">⚠️</p>
              <h2 className="text-xl font-black text-white italic uppercase">Eliminar Empresa</h2>
              <p className="text-slate-400 text-sm mt-2">Esta acción no se puede deshacer.</p>
              <p className="text-white font-bold mt-1">{confirmDelete.name}</p>
            </div>
            <div className="flex gap-3">
              <button onClick={() => setConfirmDelete(null)}
                className="flex-1 py-3 bg-white/5 hover:bg-white/10 text-slate-400 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">Cancelar</button>
              <button onClick={handleDelete} disabled={actionLoading.startsWith('delete_')}
                className="flex-1 py-3 bg-red-600 hover:bg-red-500 text-white rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">
                {actionLoading.startsWith('delete_') ? '...' : 'ELIMINAR'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ── Componentes de vista ──────────────────────────────────────────────────

interface ViewProps {
  companies: Company[];
  payments: Record<string, boolean>;
  actionLoading: string;
  onToggle: (c: Company) => void;
  onPayment: (c: Company) => void;
  onExtend: (c: Company) => void;
  onDelete: (c: Company) => void;
}

function ActionButtons({ company, payments, actionLoading, onToggle, onPayment, onExtend, onDelete }: ViewProps & { company: Company }) {
  const hasPaid = payments[company.id];
  const isStatusLoading = actionLoading === company.id + '_status';
  return (
    <div className="flex flex-wrap gap-2">
      <button onClick={() => onToggle(company)} disabled={isStatusLoading}
        className={`px-3 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all border ${
          company.status === 'active'
            ? 'bg-red-500/10 text-red-400 border-red-500/20 hover:bg-red-500/20'
            : 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20 hover:bg-emerald-500/20'
        }`}>
        {isStatusLoading ? '...' : company.status === 'active' ? 'Suspender' : 'Activar'}
      </button>
      <button onClick={() => onPayment(company)}
        className="px-3 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-wider bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 hover:bg-indigo-500/20 transition-all">
        💳 Pago
      </button>
      <button onClick={() => onExtend(company)} disabled={!hasPaid}
        title={!hasPaid ? 'Registra un pago primero' : 'Extender contrato'}
        className={`px-3 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all border ${
          hasPaid
            ? 'bg-amber-500/10 text-amber-400 border-amber-500/20 hover:bg-amber-500/20'
            : 'bg-slate-800/50 text-slate-600 border-slate-700/30 cursor-not-allowed'
        }`}>
        📅 Extender
      </button>
      <button onClick={() => onDelete(company)}
        className="px-3 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-wider bg-red-500/10 text-red-400 border border-red-500/20 hover:bg-red-500/20 transition-all">
        🗑
      </button>
    </div>
  );
}

function ListaView(props: ViewProps) {
  const { companies } = props;
  if (companies.length === 0) return <EmptyState />;
  return (
    <div className="space-y-3">
      {companies.map(c => (
        <div key={c.id} className="glass-card rounded-2xl p-5 border-white/5 bg-white/5 hover:bg-white/[0.07] transition-all">
          <div className="flex flex-col lg:flex-row lg:items-center gap-4">
            <div className="flex items-center gap-3 flex-1 min-w-0">
              <div className="w-10 h-10 rounded-xl bg-indigo-600/20 border border-indigo-500/30 flex items-center justify-center font-black text-indigo-400 flex-shrink-0">
                {c.name[0]}
              </div>
              <div className="min-w-0">
                <p className="text-sm font-bold text-white truncate">{c.name}</p>
                <p className="text-xs text-slate-500 truncate">{c.primary_email}</p>
              </div>
            </div>
            {/* Folios bar */}
            <div className="flex items-center gap-2 min-w-[130px]">
              <div className="flex-1 h-1.5 bg-slate-800 rounded-full overflow-hidden">
                <div className="h-full bg-indigo-500 transition-all"
                  style={{ width: `${Math.min((c.used_folios_count / Math.max(c.total_folios_contracted, 1)) * 100, 100)}%` }} />
              </div>
              <span className="text-xs font-black text-white whitespace-nowrap">{c.used_folios_count}/{c.total_folios_contracted}</span>
            </div>
            <DaysChip company={c} />
            <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-xl text-[10px] font-black uppercase tracking-wider border flex-shrink-0 ${STATUS_STYLE[c.status]}`}>
              <span className={`w-1.5 h-1.5 rounded-full ${c.status === 'active' ? 'bg-emerald-400 animate-pulse' : 'bg-current'}`} />
              {c.status}
            </span>
            <ActionButtons company={c} {...props} />
          </div>
        </div>
      ))}
    </div>
  );
}

function GridView(props: ViewProps) {
  const { companies } = props;
  if (companies.length === 0) return <EmptyState />;
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-5">
      {companies.map(c => {
        const d = daysLeft(c);
        const pct = Math.min((c.used_folios_count / Math.max(c.total_folios_contracted, 1)) * 100, 100);
        return (
          <div key={c.id} className="glass-card rounded-[2rem] p-6 border-white/5 bg-white/5 hover:bg-white/[0.07] transition-all flex flex-col gap-4">
            {/* Header */}
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 rounded-2xl bg-indigo-600/20 border border-indigo-500/30 flex items-center justify-center font-black text-indigo-400 text-lg flex-shrink-0">
                  {c.name[0]}
                </div>
                <div>
                  <p className="text-sm font-bold text-white leading-tight">{c.name}</p>
                  <p className="text-[11px] text-slate-500 truncate max-w-[140px]">{c.primary_email}</p>
                </div>
              </div>
              <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-xl text-[9px] font-black uppercase tracking-wider border flex-shrink-0 ${STATUS_STYLE[c.status]}`}>
                <span className={`w-1.5 h-1.5 rounded-full ${c.status === 'active' ? 'bg-emerald-400 animate-pulse' : 'bg-current'}`} />
                {c.status}
              </span>
            </div>

            {/* Folios */}
            <div>
              <div className="flex justify-between text-[10px] mb-1">
                <span className="text-slate-500 uppercase tracking-widest font-black">Folios</span>
                <span className="text-white font-black">{c.used_folios_count}/{c.total_folios_contracted}</span>
              </div>
              <div className="h-2 bg-slate-800 rounded-full overflow-hidden">
                <div className={`h-full rounded-full transition-all ${pct > 90 ? 'bg-red-500' : pct > 70 ? 'bg-amber-500' : 'bg-indigo-500'}`}
                  style={{ width: `${pct}%` }} />
              </div>
            </div>

            {/* Contrato */}
            <div className="flex justify-between items-center text-xs">
              <span className="text-slate-500">Contrato</span>
              <DaysChip company={c} />
            </div>
            {c.contract_start && (
              <div className="flex justify-between text-[10px] text-slate-600 -mt-2">
                <span>{new Date(c.contract_start).toLocaleDateString('es-MX')}</span>
                <span>{c.contract_end ? new Date(c.contract_end).toLocaleDateString('es-MX') : '—'}</span>
              </div>
            )}

            {/* Acciones */}
            <div className="pt-1 border-t border-white/5">
              <ActionButtons company={c} {...props} />
            </div>
          </div>
        );
      })}
    </div>
  );
}

function EmptyState() {
  return (
    <div className="glass-card rounded-[2.5rem] p-16 text-center border-white/5 bg-white/5">
      <p className="text-4xl mb-3">🏢</p>
      <p className="text-slate-500 text-xs font-black uppercase tracking-widest">Sin empresas registradas</p>
    </div>
  );
}
