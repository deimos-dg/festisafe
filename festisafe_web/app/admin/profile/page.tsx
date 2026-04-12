'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { fetchWithAuth, getUser, clearToken, saveToken, authApi } from '@/lib/api';

export default function ProfilePage() {
  const router = useRouter();
  const user = getUser();

  const [tab, setTab] = useState<'info' | 'password'>('info');
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState('');
  const [error, setError] = useState('');

  // Info form
  const [name, setName] = useState((user?.name as string) || '');
  const [phone, setPhone] = useState((user?.phone as string) || '');

  // Password form
  const [currentPwd, setCurrentPwd] = useState('');
  const [newPwd, setNewPwd] = useState('');
  const [confirmPwd, setConfirmPwd] = useState('');

  function clearMessages() { setSuccess(''); setError(''); }

  async function handleUpdateInfo(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    clearMessages();
    setLoading(true);
    try {
      const updated = await fetchWithAuth('/users/me', {
        method: 'PATCH',
        body: JSON.stringify({ name: name.trim(), phone: phone.trim() || undefined }),
      });
      // Actualizar sessionStorage con los nuevos datos
      const role = (user?.role as string) || undefined;
      saveToken(
        (sessionStorage.getItem('festisafe_token') || ''),
        role,
        { ...user, name: updated.name, phone: updated.phone },
      );
      setSuccess('Perfil actualizado correctamente');
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Error al actualizar');
    } finally {
      setLoading(false);
    }
  }

  async function handleChangePassword(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    clearMessages();
    if (newPwd !== confirmPwd) { setError('Las contraseñas no coinciden'); return; }
    setLoading(true);
    try {
      await fetchWithAuth('/users/me/change-password', {
        method: 'POST',
        body: JSON.stringify({
          current_password: currentPwd,
          new_password: newPwd,
          confirm_password: confirmPwd,
        }),
      });
      // Re-login para obtener token fresco con nueva contraseña
      const email = user?.email as string;
      const data = await authApi.login(email, newPwd);
      saveToken(data.access_token, data.user?.role, data.user);
      setCurrentPwd(''); setNewPwd(''); setConfirmPwd('');
      setSuccess('Contraseña actualizada. Sesión renovada.');
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Error al cambiar contraseña');
    } finally {
      setLoading(false);
    }
  }

  function handleLogout() {
    clearToken();
    router.push('/');
  }

  return (
    <div className="relative min-h-screen p-8 lg:p-12 max-w-2xl">
      <header className="mb-10">
        <h1 className="text-4xl font-black text-white tracking-tight flex items-center gap-3 italic uppercase">
          <span className="w-2 h-8 bg-indigo-500 rounded-full inline-block" />
          Mi Perfil
        </h1>
        <p className="text-slate-500 text-xs font-black uppercase tracking-[0.3em] ml-5 mt-1">
          Configuración de cuenta
        </p>
      </header>

      {/* Avatar + info básica */}
      <div className="glass-card rounded-[2rem] p-6 border-white/5 bg-white/5 mb-8 flex items-center gap-5">
        <div className="w-16 h-16 rounded-2xl bg-indigo-600/20 border border-indigo-500/30 flex items-center justify-center font-black text-indigo-400 text-2xl flex-shrink-0">
          {((user?.name as string) || 'A')[0]?.toUpperCase()}
        </div>
        <div>
          <p className="text-lg font-black text-white">{(user?.name as string) || '—'}</p>
          <p className="text-sm text-slate-400">{(user?.email as string) || '—'}</p>
          <span className="inline-flex items-center gap-1.5 mt-1 px-2.5 py-1 rounded-xl text-[10px] font-black uppercase tracking-wider bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
            {(user?.role as string) === 'admin' ? '👑 Super Admin' : '🛡️ Admin'}
          </span>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 mb-6">
        {(['info', 'password'] as const).map(t => (
          <button key={t} onClick={() => { setTab(t); clearMessages(); }}
            className={`px-5 py-2.5 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all border ${
              tab === t
                ? 'bg-indigo-600 text-white border-indigo-500'
                : 'bg-white/5 text-slate-400 border-white/10 hover:bg-white/10'
            }`}>
            {t === 'info' ? '👤 Información' : '🔐 Contraseña'}
          </button>
        ))}
      </div>

      {/* Mensajes */}
      {success && (
        <div className="mb-5 bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 p-4 rounded-2xl text-xs font-bold">
          ✅ {success}
        </div>
      )}
      {error && (
        <div className="mb-5 bg-red-500/10 border border-red-500/20 text-red-400 p-4 rounded-2xl text-xs font-bold">
          ⚠️ {error}
        </div>
      )}

      {/* Tab: Información */}
      {tab === 'info' && (
        <form onSubmit={handleUpdateInfo} className="glass-card rounded-[2rem] p-6 border-white/5 bg-white/5 space-y-5">
          <div className="space-y-1">
            <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Nombre</label>
            <input type="text" required className="premium-input" value={name}
              onChange={e => setName(e.target.value)} />
          </div>
          <div className="space-y-1">
            <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Email</label>
            <input type="email" disabled className="premium-input opacity-50 cursor-not-allowed"
              value={(user?.email as string) || ''} />
            <p className="text-[10px] text-slate-600 ml-3">El email no se puede cambiar</p>
          </div>
          <div className="space-y-1">
            <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Teléfono (opcional)</label>
            <input type="tel" className="premium-input" placeholder="+52 55 1234 5678"
              value={phone} onChange={e => setPhone(e.target.value)} />
          </div>
          <button type="submit" disabled={loading} className="premium-button w-full">
            {loading ? 'Guardando...' : 'GUARDAR CAMBIOS'}
          </button>
        </form>
      )}

      {/* Tab: Contraseña */}
      {tab === 'password' && (
        <form onSubmit={handleChangePassword} className="glass-card rounded-[2rem] p-6 border-white/5 bg-white/5 space-y-5">
          <div className="space-y-1">
            <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Contraseña actual</label>
            <input type="password" required className="premium-input"
              value={currentPwd} onChange={e => setCurrentPwd(e.target.value)} />
          </div>
          <div className="space-y-1">
            <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Nueva contraseña</label>
            <input type="password" required minLength={12} className="premium-input"
              placeholder="Mín. 12 chars, mayúscula, número, especial"
              value={newPwd} onChange={e => setNewPwd(e.target.value)} />
          </div>
          <div className="space-y-1">
            <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-3">Confirmar contraseña</label>
            <input type="password" required className="premium-input"
              value={confirmPwd} onChange={e => setConfirmPwd(e.target.value)} />
          </div>
          <button type="submit" disabled={loading} className="premium-button w-full">
            {loading ? 'Actualizando...' : 'CAMBIAR CONTRASEÑA'}
          </button>
        </form>
      )}

      {/* Zona de peligro */}
      <div className="mt-8 glass-card rounded-[2rem] p-6 border-red-500/10 bg-red-500/5">
        <p className="text-[10px] font-black text-red-400 uppercase tracking-widest mb-4">Zona de peligro</p>
        <button onClick={handleLogout}
          className="w-full py-3 bg-red-600/20 hover:bg-red-600/30 text-red-400 border border-red-500/20 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">
          🚪 Cerrar sesión en todos los dispositivos
        </button>
      </div>
    </div>
  );
}
