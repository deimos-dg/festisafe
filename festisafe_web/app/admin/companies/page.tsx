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

interface Transaction {
  id: string;
  status: string;
}

export default function AdminCompaniesPage() {
  const [companies, setCompanies] = useState<Company[]>([]);
  const [payments, setPayments] = useState<Record<string, boolean>>({});
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [showPaymentModal, setShowPaymentModal] = useState<Company | null>(null);
  const [showExtendModal, setShowExtendModal] = useState<Company | null>(null);
  const [formData, setFormData] = useState({ name: '', primary_email: '', total_folios_contracted: 50 });
  const [paymentForm, setPaymentForm] = useState({ amount: '', method: 'transfer', description: '' });
  const [extendDays, setExtendDays] = useState(30);
  const [actionLoading, setActionLoading] = useState('');

  useEffect(() => { loadAll(); }, []);

  async function loadAll() {
    try {
      const data = await adminApi.getCompanies();
      setCompanies(data);
      // Verificar si cada empresa tiene pagos completados
      const txData = await fetchWithAuth('/billing/transactions').catch(() => []);
      const paidMap: Record<string, boolean> = {};
      for (const tx of txData) {
        if (tx.status === 'completed') paidMap[tx.company_id || tx.company] = true;
      }
      // Alternativa: verificar por nombre de empresa en transactions
      for (const c of data) {
        const hasPaid = txData.some((tx: Transaction & { company: string }) =>
          tx.status === 'completed'
        );
        if (!paidMap[c.id]) paidMap[c.id] = false;
      }
      setPayments(paidMap);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  }

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    setActionLoading('create');
    try {
      await adminApi.createCompany(formData);
      setShowModal(false);
      setFormData({ name: '', primary_email: '', total_folios_contracted: 50 });
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

  async function handleManualPayment(e: React.FormEvent) {
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

  async function handleExtend(e: React.FormEvent) {
    e.preventDefault();
    if (!showExtendModal) return;
    setActionLoading('extend');
    try {
      await fetchWithAuth(
        `/companies/${showExtendModal.id}/extend?days=${extendDays}&payment_method=manual`,
        { method: 'POST' }
      );
      setShowExtendModal(null);
      loadAll();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Error al extender contrato';
      alert(msg);
    }
    finally { setActionLoading(''); }
  }

  function contractDaysLeft(company: Company): number | null {
    if (!company.contract_end) return null;
    const diff = new Date(company.contract_end).getTime() - Date.now();
    return Math.ceil(diff / (1000 * 60 * 60 * 24));
  }

  return (
    <div className="relative min-h-screen p-8 lg:p-12">
      <header className="flex flex-col md:flex-row justify-between items-start md:items-center mb-12 gap-6">
        <div className="space-y-1">
          <h1 className="text-4xl font-black text-white tracking-tight flex items-center gap-3 italic uppercase">
            <span className="w-2 h-8 bg-indigo-500 rounded-full inline-block" />
            Empresas <span className="text-indigo-400 not-italic font-medium text-xl ml-2 tracking-widest">Fleet Control</span>
          </h1>
          <p className="text-slate-500 text-xs font-black uppercase tracking-[0.3em] ml-5">
            Gestión Global de Clientes y Contratos
          </p>
        </div>
        <button onClick={() => setShowModal(true)} className="premium-button flex items-center gap-3 px-8 group">
          <span className="text-lg group-hover:rotate-90 transition-transform inline-block">+</span>
          ALTA DE NUEVA EMPRESA
        </button>
      </header>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
        <div className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Total Clientes</p>
          <p className="text-3xl font-black text-white">{companies.length}</p>
        </div>
        <div className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Activas</p>
          <p className="text-3xl font-black text-emerald-400">{companies.filter(c => c.status === 'active').length}</p>
        </div>
        <div className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Suspendidas</p>
          <p className="text-3xl font-black text-red-400">{companies.filter(c => c.status === 'suspended').length}</p>
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center items-center h-64">
          <div className="w-12 h-12 border-4 border-indigo-500/20 border-t-indigo-500 rounded-full animate-spin" />
        </div>
      ) : (
        <div className="space-y-4">
          {companies.map((company) => {
            const daysLeft = contractDaysLeft(company);
            const hasPaid = payments[company.id];
            const isStatusLoading = actionLoading === company.id + '_status';
            return (
              <div key={company.id} className="glass-card rounded-[2rem] p-6 border-white/5 bg-white/5 hover:bg-white/[0.07] transition-all">
                <div className="flex flex-col lg:flex-row lg:items-center gap-6">
                  {/* Info */}
                  <div className="flex items-center gap-4 flex-1">
                    <div className="w-12 h-12 rounded-2xl bg-indigo-600/20 border border-indigo-500/30 flex items-center justify-center font-black text-indigo-400 text-lg italic flex-shrink-0">
                      {company.name[0]}
                    </div>
                    <div>
                      <p className="text-sm font-bold text-white">{company.name}</p>
                      <p className="text-xs text-slate-500">{company.primary_email}</p>
                    </div>
                  </div>

                  {/* Folios */}
                  <div className="flex items-center gap-3 min-w-[140px]">
                    <div className="flex-1 h-1.5 bg-slate-800 rounded-full overflow-hidden">
                      <div
                        className="h-full bg-indigo-500"
                        style={{ width: `${Math.min((company.used_folios_count / Math.max(company.total_folios_contracted, 1)) * 100, 100)}%` }}
                      />
                    </div>
                    <span className="text-xs font-black text-white whitespace-nowrap">
                      {company.used_folios_count}/{company.total_folios_contracted}
                    </span>
                  </div>

                  {/* Contrato */}
                  <div className="min-w-[120px]">
                    {daysLeft !== null ? (
                      <span className={`text-xs font-black ${daysLeft > 7 ? 'text-emerald-400' : daysLeft > 0 ? 'text-amber-400' : 'text-red-400'}`}>
                        {daysLeft > 0 ? `${daysLeft}d restantes` : 'Expirado'}
                      </span>
                    ) : (
                      <span className="text-xs text-slate-600">Sin fecha fin</span>
                    )}
                  </div>

                  {/* Status badge */}
                  <span className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-wider flex-shrink-0 ${
                    company.status === 'active'
                      ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
                      : 'bg-red-500/10 text-red-400 border border-red-500/20'
                  }`}>
                    <span className={`w-1.5 h-1.5 rounded-full ${company.status === 'active' ? 'bg-emerald-400 animate-pulse' : 'bg-red-400'}`} />
                    {company.status}
                  </span>

                  {/* Acciones */}
                  <div className="flex items-center gap-2 flex-shrink-0">
                    {/* Toggle activo/suspendido */}
                    <button
                      onClick={() => toggleStatus(company)}
                      disabled={isStatusLoading}
                      className={`px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all ${
                        company.status === 'active'
                          ? 'bg-red-500/10 text-red-400 border border-red-500/20 hover:bg-red-500/20'
                          : 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 hover:bg-emerald-500/20'
                      }`}
                    >
                      {isStatusLoading ? '...' : company.status === 'active' ? 'Suspender' : 'Activar'}
                    </button>

                    {/* Registrar pago manual */}
                    <button
                      onClick={() => setShowPaymentModal(company)}
                      className="px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-wider bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 hover:bg-indigo-500/20 transition-all"
                    >
                      💳 Pago
                    </button>

                    {/* Extender días — solo si tiene pago completado */}
                    <button
                      onClick={() => setShowExtendModal(company)}
                      disabled={!hasPaid}
                      title={!hasPaid ? 'Registra un pago primero' : 'Extender contrato'}
                      className={`px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all ${
                        hasPaid
                          ? 'bg-amber-500/10 text-amber-400 border border-amber-500/20 hover:bg-amber-500/20'
                          : 'bg-slate-800/50 text-slate-600 border border-slate-700/30 cursor-not-allowed'
                      }`}
                    >
                      📅 Extender
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Modal: Nueva empresa */}
      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-6 backdrop-blur-md bg-black/40">
          <div className="glass-card rounded-[3rem] p-10 max-w-md w-full border-white/10 shadow-[0_0_50px_rgba(0,0,0,0.5)]">
            <h2 className="text-2xl font-black text-white mb-8 italic uppercase tracking-tight">Nueva Empresa</h2>
            <form onSubmit={handleCreate} className="space-y-6">
              <div className="space-y-2">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Nombre Comercial</label>
                <input type="text" required className="premium-input w-full" placeholder="Ej. Security Global SA"
                  value={formData.name} onChange={e => setFormData({...formData, name: e.target.value})} />
              </div>
              <div className="space-y-2">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Email Operativo</label>
                <input type="email" required className="premium-input w-full" placeholder="contact@company.com"
                  value={formData.primary_email} onChange={e => setFormData({...formData, primary_email: e.target.value})} />
              </div>
              <div className="space-y-2">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Folios Iniciales</label>
                <input type="number" required className="premium-input w-full" value={formData.total_folios_contracted}
                  onChange={e => setFormData({...formData, total_folios_contracted: parseInt(e.target.value)})} />
              </div>
              <div className="flex gap-4 pt-4">
                <button type="button" onClick={() => setShowModal(false)}
                  className="flex-1 py-4 bg-white/5 hover:bg-white/10 text-slate-400 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">
                  Cancelar
                </button>
                <button type="submit" disabled={actionLoading === 'create'} className="flex-1 premium-button">
                  {actionLoading === 'create' ? '...' : 'CONFIRMAR'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: Registrar pago manual */}
      {showPaymentModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-6 backdrop-blur-md bg-black/40">
          <div className="glass-card rounded-[3rem] p-10 max-w-md w-full border-white/10 shadow-[0_0_50px_rgba(0,0,0,0.5)]">
            <h2 className="text-2xl font-black text-white mb-2 italic uppercase tracking-tight">Registrar Pago</h2>
            <p className="text-slate-500 text-xs mb-8">{showPaymentModal.name}</p>
            <form onSubmit={handleManualPayment} className="space-y-6">
              <div className="space-y-2">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Monto (MXN)</label>
                <input type="number" required min="1" step="0.01" className="premium-input w-full" placeholder="500.00"
                  value={paymentForm.amount} onChange={e => setPaymentForm({...paymentForm, amount: e.target.value})} />
              </div>
              <div className="space-y-2">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Método de Pago</label>
                <select className="premium-input w-full" value={paymentForm.method}
                  onChange={e => setPaymentForm({...paymentForm, method: e.target.value})}>
                  <option value="transfer">Transferencia bancaria</option>
                  <option value="cash">Efectivo</option>
                  <option value="stripe">Stripe (manual)</option>
                </select>
              </div>
              <div className="space-y-2">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Descripción (opcional)</label>
                <input type="text" className="premium-input w-full" placeholder="Ej. Pago evento 15 mayo"
                  value={paymentForm.description} onChange={e => setPaymentForm({...paymentForm, description: e.target.value})} />
              </div>
              <div className="flex gap-4 pt-4">
                <button type="button" onClick={() => setShowPaymentModal(null)}
                  className="flex-1 py-4 bg-white/5 hover:bg-white/10 text-slate-400 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">
                  Cancelar
                </button>
                <button type="submit" disabled={actionLoading === 'payment'} className="flex-1 premium-button">
                  {actionLoading === 'payment' ? '...' : 'REGISTRAR PAGO'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: Extender contrato */}
      {showExtendModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-6 backdrop-blur-md bg-black/40">
          <div className="glass-card rounded-[3rem] p-10 max-w-md w-full border-white/10 shadow-[0_0_50px_rgba(0,0,0,0.5)]">
            <h2 className="text-2xl font-black text-white mb-2 italic uppercase tracking-tight">Extender Contrato</h2>
            <p className="text-slate-500 text-xs mb-8">{showExtendModal.name}</p>
            {showExtendModal.contract_end && (
              <p className="text-xs text-slate-400 mb-6">
                Vence: <span className="text-white font-bold">{new Date(showExtendModal.contract_end).toLocaleDateString('es-MX')}</span>
              </p>
            )}
            <form onSubmit={handleExtend} className="space-y-6">
              <div className="space-y-2">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Días a extender</label>
                <input type="number" required min="1" max="3650" className="premium-input w-full"
                  value={extendDays} onChange={e => setExtendDays(parseInt(e.target.value))} />
                <p className="text-[10px] text-slate-600 ml-4">
                  Nueva fecha fin: {(() => {
                    const base = showExtendModal.contract_end
                      ? new Date(showExtendModal.contract_end)
                      : new Date();
                    base.setDate(base.getDate() + extendDays);
                    return base.toLocaleDateString('es-MX');
                  })()}
                </p>
              </div>
              <div className="flex gap-4 pt-4">
                <button type="button" onClick={() => setShowExtendModal(null)}
                  className="flex-1 py-4 bg-white/5 hover:bg-white/10 text-slate-400 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">
                  Cancelar
                </button>
                <button type="submit" disabled={actionLoading === 'extend'} className="flex-1 premium-button">
                  {actionLoading === 'extend' ? '...' : `EXTENDER ${extendDays} DÍAS`}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
