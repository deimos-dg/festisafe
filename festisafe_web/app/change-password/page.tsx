'use client';

import { useState, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { fetchWithAuth, saveToken, authApi } from '@/lib/api';

function ChangePasswordForm() {
  const router = useRouter();
  const params = useSearchParams();
  const email = params.get('email') || '';

  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (next !== confirm) { setError('Las contraseñas no coinciden'); return; }
    setLoading(true);
    setError('');
    try {
      // Primero hacer login para obtener token con allow_password_change
      const loginData = await authApi.login(email, current).catch(() => null);
      // Si el login falla por must_change_password el backend devuelve 403
      // Usamos el endpoint de change-password de auth que acepta must_change_password
      const res = await fetch(
        `${process.env.NEXT_PUBLIC_API_URL || 'https://festisafe-production.up.railway.app'}/api/v1/auth/change-password`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            ...(loginData ? { Authorization: `Bearer ${loginData.access_token}` } : {}),
          },
          body: JSON.stringify({ current_password: current, new_password: next, confirm_password: confirm }),
        }
      );
      if (!res.ok) {
        const d = await res.json().catch(() => ({}));
        throw new Error(d.detail || 'Error al cambiar contraseña');
      }
      // Login con nueva contraseña
      const data = await authApi.login(email, next);
      saveToken(data.access_token, data.user?.role, data.user);
      router.push('/admin/companies');
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Error inesperado');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-6">
      <div className="glass-card rounded-[2.5rem] p-10 max-w-md w-full border-white/10">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-14 h-14 bg-amber-500/20 rounded-3xl mb-4 border border-amber-500/30">
            <span className="text-2xl">🔐</span>
          </div>
          <h1 className="text-2xl font-black text-white uppercase italic tracking-tight">Cambio de Contraseña</h1>
          <p className="text-slate-500 text-xs mt-2 uppercase tracking-widest font-bold">
            Requerido antes de continuar
          </p>
        </div>

        {error && (
          <div className="bg-red-500/10 border border-red-500/20 text-red-400 p-4 rounded-2xl text-[11px] font-black uppercase tracking-wider text-center mb-6">
            ⚠️ {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-5">
          <div className="space-y-2">
            <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Contraseña temporal</label>
            <input type="password" required className="premium-input w-full"
              value={current} onChange={e => setCurrent(e.target.value)} />
          </div>
          <div className="space-y-2">
            <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Nueva contraseña</label>
            <input type="password" required className="premium-input w-full"
              placeholder="Mín. 12 chars, mayúscula, número, especial"
              value={next} onChange={e => setNext(e.target.value)} />
          </div>
          <div className="space-y-2">
            <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Confirmar contraseña</label>
            <input type="password" required className="premium-input w-full"
              value={confirm} onChange={e => setConfirm(e.target.value)} />
          </div>
          <button type="submit" disabled={loading}
            className={`w-full py-4 rounded-2xl font-black text-[11px] uppercase tracking-[0.3em] text-white transition-all ${
              loading ? 'bg-slate-800 cursor-not-allowed' : 'bg-indigo-600 hover:bg-indigo-500'
            }`}>
            {loading ? 'Procesando...' : 'Establecer nueva contraseña'}
          </button>
        </form>
      </div>
    </div>
  );
}

export default function ChangePasswordPage() {
  return (
    <Suspense>
      <ChangePasswordForm />
    </Suspense>
  );
}
