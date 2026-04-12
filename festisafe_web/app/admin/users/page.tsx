'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { fetchWithAuth, isSuperAdmin } from '@/lib/api';

interface StaffUser {
  id: string;
  name: string;
  email: string;
  role: 'admin' | 'user';
  is_active: boolean;
  created_at: string;
}

const ROLE_LABELS: Record<string, string> = { admin: 'Admin', user: 'Viewer' };
const ROLE_STYLES: Record<string, string> = {
  admin: 'bg-indigo-500/10 text-indigo-400 border-indigo-500/20',
  user: 'bg-slate-500/10 text-slate-400 border-slate-500/20',
};

export default function UsersPage() {
  const router = useRouter();
  const [users, setUsers] = useState<StaffUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [actionLoading, setActionLoading] = useState('');
  const [form, setForm] = useState({ name: '', email: '', password: '', role: 'admin' });
  const [formError, setFormError] = useState('');

  useEffect(() => {
    if (!isSuperAdmin()) { router.replace('/admin'); return; }
    loadUsers();
  }, []);

  async function loadUsers() {
    try {
      const data = await fetchWithAuth('/admin/users?role=admin&limit=200');
      setUsers(Array.isArray(data) ? data : []);
    } catch (e) { console.error(e); }
    finally { setLoading(false); }
  }

  async function handleCreate(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setFormError('');
    setActionLoading('create');
    try {
      const res = await fetch(
        `${process.env.NEXT_PUBLIC_API_URL || 'https://festisafe-production.up.railway.app'}/api/v1/auth/register`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            name: form.name, email: form.email,
            password: form.password, confirm_password: form.password,
            is_organizer: false,
          }),
        }
      );
      if (!res.ok) {
        const d = await res.json().catch(() => ({}));
        throw new Error(d.detail || 'Error al crear usuario');
      }
      const created = await res.json();
      if (form.role === 'admin') {
        await fetchWithAuth(`/users/${created.user_id}/role?role=admin`, { method: 'PATCH' });
      }
      setShowModal(false);
      setForm({ name: '', email: '', password: '', role: 'admin' });
      loadUsers();
    } catch (err: unknown) {
      setFormError(err instanceof Error ? err.message : 'Error inesperado');
    } finally { setActionLoading(''); }
  }

  async function toggleActive(user: StaffUser) {
    setActionLoading(user.id);
    try {
      const ep = user.is_active
        ? `/admin/users/${user.id}/deactivate`
        : `/admin/users/${user.id}/activate`;
      await fetchWithAuth(ep, { method: 'PATCH' });
      loadUsers();
    } catch { alert('Error al cambiar estado'); }
    finally { setActionLoading(''); }
  }

  return (
    <div className="relative min-h-screen p-8 lg:p-12">
      <header className="flex flex-col md:flex-row justify-between items-start md:items-center mb-10 gap-6">
        <div className="space-y-1">
          <h1 className="text-4xl font-black text-white tracking-tight flex items-center gap-3 italic uppercase">
            <span className="w-2 h-8 bg-indigo-500 rounded-full inline-block" />
            Mi Equipo{' '}
            <span className="text-indigo-400 not-italic font-medium text-xl ml-2 tracking-widest">
              Staff Control
            </span>
          </h1>
          <p className="text-slate-500 text-xs font-black uppercase tracking-[0.3em] ml-5">
            Usuarios internos de FestiSafe
          </p>
        </div>
        <button onClick={() => setShowModal(true)} className="premium-button flex items-center gap-2 px-6">
          <span>+</span> Nuevo Empleado
        </button>
      </header>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
        <div className="glass-card rounded-2xl p-4 border-indigo-500/10 bg-indigo-500/5">
          <p className="text-xs font-black text-indigo-400 uppercase tracking-widest mb-1">� Admin</p>
          <p className="text-[11px] text-slate-400">
            Gestiona empresas, activa/suspende clientes y registra pagos. Sin acceso a facturación ni a este panel.
          </p>
        </div>
        <div className="glass-card rounded-2xl p-4 border-slate-500/10 bg-slate-500/5">
          <p className="text-xs font-black text-slate-400 uppercase tracking-widest mb-1">👁 Viewer</p>
          <p className="text-[11px] text-slate-400">
            Solo lectura: ve empresas y mapa en vivo. Sin acciones de escritura.
          </p>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-4 mb-8">
        {[
          { label: 'Total', val: users.length, color: 'text-white' },
          { label: 'Activos', val: users.filter(u => u.is_active).length, color: 'text-emerald-400' },
          { label: 'Inactivos', val: users.filter(u => !u.is_active).length, color: 'text-slate-500' },
        ].map((s, i) => (
          <div key={i} className="glass-card p-4 rounded-2xl border-white/5 bg-white/5 text-center">
            <p className="text-[9px] font-black text-slate-500 uppercase tracking-widest mb-1">{s.label}</p>
            <p className={`text-2xl font-black ${s.color}`}>{s.val}</p>
          </div>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="w-10 h-10 border-4 border-indigo-500/20 border-t-indigo-500 rounded-full animate-spin" />
        </div>
      ) : users.length === 0 ? (
        <div className="glass-card rounded-[2.5rem] p-16 text-center border-white/5 bg-white/5">
          <p className="text-4xl mb-3">👥</p>
          <p className="text-slate-500 text-xs font-black uppercase tracking-widest">Sin empleados registrados</p>
        </div>
      ) : (
        <div className="glass-card rounded-[2rem] overflow-hidden border-white/5">
          <table className="w-full text-left">
            <thead>
              <tr className="bg-white/[0.02] border-b border-white/5">
                {['Empleado', 'Rol', 'Alta', 'Estado', 'Acción'].map(h => (
                  <th key={h} className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-white/[0.02]">
              {users.map(u => (
                <tr key={u.id} className="hover:bg-white/[0.03] transition-colors">
                  <td className="px-6 py-4">
                    <div className="flex items-center gap-3">
                      <div className="w-9 h-9 rounded-xl bg-indigo-600/20 border border-indigo-500/20 flex items-center justify-center font-black text-indigo-400 text-sm">
                        {u.name[0]?.toUpperCase()}
                      </div>
                      <div>
                        <p className="text-sm font-bold text-white">{u.name}</p>
                        <p className="text-[11px] text-slate-500">{u.email}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4">
                    <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-xl text-[10px] font-black uppercase tracking-wider border ${ROLE_STYLES[u.role] || ''}`}>
                      {ROLE_LABELS[u.role] || u.role}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-xs text-slate-500">
                    {new Date(u.created_at).toLocaleDateString('es-MX')}
                  </td>
                  <td className="px-6 py-4">
                    <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-xl text-[10px] font-black uppercase tracking-wider border ${
                      u.is_active
                        ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20'
                        : 'bg-slate-500/10 text-slate-500 border-slate-500/20'
                    }`}>
                      <span className={`w-1.5 h-1.5 rounded-full ${u.is_active ? 'bg-emerald-400 animate-pulse' : 'bg-slate-500'}`} />
                      {u.is_active ? 'Activo' : 'Inactivo'}
                    </span>
                  </td>
                  <td className="px-6 py-4">
                    <button
                      onClick={() => toggleActive(u)}
                      disabled={actionLoading === u.id}
                      className={`px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all border ${
                        u.is_active
                          ? 'bg-red-500/10 text-red-400 border-red-500/20 hover:bg-red-500/20'
                          : 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20 hover:bg-emerald-500/20'
                      }`}
                    >
                      {actionLoading === u.id ? '...' : u.is_active ? 'Desactivar' : 'Activar'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-6 backdrop-blur-md bg-black/50">
          <div className="glass-card rounded-[2.5rem] p-8 max-w-md w-full border-white/10 shadow-[0_0_60px_rgba(0,0,0,0.6)]">
            <h2 className="text-xl font-black text-white mb-1 italic uppercase">Nuevo Empleado</h2>
            <p className="text-slate-500 text-xs mb-6 uppercase tracking-widest">Acceso al panel de administración</p>
            {formError && (
              <div className="mb-4 bg-red-500/10 border border-red-500/20 text-red-400 p-3 rounded-xl text-xs font-bold">
                ⚠️ {formError}
              </div>
            )}
            <form onSubmit={handleCreate} className="space-y-4">
              <div className="space-y-1">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Nombre completo</label>
                <input type="text" required className="premium-input" placeholder="Ej. Carlos Ramírez"
                  value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
              </div>
              <div className="space-y-1">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Email corporativo</label>
                <input type="email" required className="premium-input" placeholder="carlos@festisafe.com"
                  value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} />
              </div>
              <div className="space-y-1">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Contraseña temporal</label>
                <input type="text" required minLength={12} className="premium-input"
                  placeholder="Mín. 12 chars, mayúscula, número, especial"
                  value={form.password} onChange={e => setForm({ ...form, password: e.target.value })} />
                <p className="text-[10px] text-slate-600 ml-3">El empleado deberá cambiarla en su primer acceso</p>
              </div>
              <div className="space-y-1">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Rol asignado</label>
                <select className="premium-input" value={form.role}
                  onChange={e => setForm({ ...form, role: e.target.value })}>
                  <option value="admin">Admin — Gestión de empresas</option>
                  <option value="user">Viewer — Solo lectura</option>
                </select>
              </div>
              <div className={`rounded-2xl p-3 border text-[10px] leading-relaxed ${
                form.role === 'admin'
                  ? 'bg-indigo-500/5 border-indigo-500/20 text-indigo-300'
                  : 'bg-slate-500/5 border-slate-500/20 text-slate-400'
              }`}>
                {form.role === 'admin'
                  ? '✅ Ver empresas · ✅ Activar/Suspender · ✅ Registrar pagos · ❌ Facturación · ❌ Gestión de equipo'
                  : '✅ Ver empresas · ✅ Ver mapa · ❌ Modificar datos · ❌ Facturación · ❌ Gestión de equipo'}
              </div>
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => { setShowModal(false); setFormError(''); }}
                  className="flex-1 py-3 bg-white/5 hover:bg-white/10 text-slate-400 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">
                  Cancelar
                </button>
                <button type="submit" disabled={actionLoading === 'create'} className="flex-1 premium-button">
                  {actionLoading === 'create' ? 'Creando...' : 'CREAR EMPLEADO'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
