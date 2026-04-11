'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { authApi } from '@/lib/api';

export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      const data = await authApi.login(email, password);
      localStorage.setItem('festisafe_token', data.access_token);
      router.push('/admin/companies');
    } catch (err: any) {
      setError(err.message || 'Credenciales inválidas');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="relative min-h-screen w-full bg-[#030712] flex items-center justify-center p-6 overflow-hidden font-sans">

      {/* Animated Background Elements */}
      <div className="absolute top-[-10%] left-[-10%] w-[40%] h-[40%] bg-indigo-600/20 rounded-full blur-[120px] animate-pulse" />
      <div className="absolute bottom-[-10%] right-[-10%] w-[40%] h-[40%] bg-purple-600/10 rounded-full blur-[120px] animate-pulse" style={{ animationDelay: '2s' }} />

      {/* Grid Pattern Overlay */}
      <div className="absolute inset-0 z-0 opacity-10 pointer-events-none"
           style={{ backgroundImage: 'radial-gradient(#ffffff 0.5px, transparent 0.5px)', backgroundSize: '30px 30px' }} />

      <div className="relative z-10 w-full max-w-[440px]">

        {/* Glassmorphism Card */}
        <div className="bg-white/[0.03] backdrop-blur-2xl border border-white/10 rounded-[2.5rem] p-10 shadow-[0_25px_50px_-12px_rgba(0,0,0,0.5)]">

          <div className="text-center mb-12">
            <div className="inline-flex items-center justify-center w-16 h-16 bg-indigo-600 rounded-3xl mb-6 shadow-2xl shadow-indigo-600/30 transform hover:scale-110 transition-transform cursor-default">
               <span className="text-white font-black text-2xl tracking-tighter">FS</span>
            </div>
            <h1 className="text-4xl font-black text-white tracking-tight mb-2 uppercase italic">
              FestiSafe
            </h1>
            <p className="text-slate-500 text-xs font-black uppercase tracking-[0.3em] italic">
              Secure Cloud Access
            </p>
          </div>

          <form onSubmit={handleLogin} className="space-y-6">
            {error && (
              <div className="bg-red-500/10 border border-red-500/20 text-red-400 p-4 rounded-2xl text-[11px] font-black uppercase tracking-wider text-center animate-shake">
                ⚠️ {error}
              </div>
            )}

            <div className="space-y-2">
              <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">
                Operations Email
              </label>
              <input
                type="email"
                required
                className="w-full bg-white/[0.05] border border-white/10 rounded-2xl px-6 py-4 text-sm text-white placeholder:text-slate-600 outline-none focus:border-indigo-500 focus:ring-4 focus:ring-indigo-500/10 transition-all"
                placeholder="admin@festisafe.systems"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
            </div>

            <div className="space-y-2">
              <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">
                Access Secret
              </label>
              <input
                type="password"
                required
                className="w-full bg-white/[0.05] border border-white/10 rounded-2xl px-6 py-4 text-sm text-white placeholder:text-slate-600 outline-none focus:border-indigo-500 focus:ring-4 focus:ring-indigo-500/10 transition-all"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </div>

            <button
              type="submit"
              disabled={loading}
              className={`relative group w-full py-5 rounded-2xl font-black text-[11px] uppercase tracking-[0.3em] text-white shadow-2xl transition-all active:scale-95 overflow-hidden ${
                loading
                  ? 'bg-slate-800 cursor-not-allowed'
                  : 'bg-indigo-600 hover:bg-indigo-500'
              }`}
            >
              {/* Button Glow Effect */}
              <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/10 to-transparent -translate-x-full group-hover:translate-x-full transition-transform duration-1000" />

              <span className="relative">
                {loading ? 'Validating Connection...' : 'Initialize Access 🔓'}
              </span>
            </button>
          </form>

          <div className="mt-12 text-center">
            <p className="text-[9px] text-slate-600 font-bold uppercase tracking-[0.2em]">
              Authorized Personnel Only
            </p>
          </div>
        </div>

        {/* Floating Decoration Footer */}
        <div className="mt-8 flex justify-center gap-8 opacity-20 group">
            <div className="h-0.5 w-12 bg-slate-700 rounded-full" />
            <div className="h-0.5 w-12 bg-slate-700 rounded-full" />
            <div className="h-0.5 w-12 bg-slate-700 rounded-full" />
        </div>
      </div>
    </div>
  );
}
