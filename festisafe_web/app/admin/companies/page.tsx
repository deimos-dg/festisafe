'use client';

import { useState, useEffect } from 'react';
import { adminApi } from '@/lib/api';

interface Company {
  id: string;
  name: string;
  primary_email: string;
  status: string;
  total_folios_contracted: number;
  used_folios_count: number;
}

export default function AdminCompaniesPage() {
  const [companies, setCompanies] = useState<Company[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    primary_email: '',
    total_folios_contracted: 50
  });

  useEffect(() => {
    loadCompanies();
  }, []);

  async function loadCompanies() {
    try {
      const data = await adminApi.getCompanies();
      setCompanies(data);
    } catch (error) {
      console.error("Error al cargar empresas:", error);
    } finally {
      setLoading(false);
    }
  }

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    try {
      await adminApi.createCompany(formData);
      setShowModal(false);
      loadCompanies();
      setFormData({ name: '', primary_email: '', total_folios_contracted: 50 });
    } catch (error) {
      alert("Error al crear la empresa");
    }
  }

  return (
    <div className="relative min-h-screen p-8 lg:p-12">

      {/* Header Sección */}
      <header className="flex flex-col md:flex-row justify-between items-start md:items-center mb-12 gap-6">
        <div className="space-y-1">
          <h1 className="text-4xl font-black text-white tracking-tight flex items-center gap-3 italic uppercase">
            <span className="w-2 h-8 bg-indigo-500 rounded-full inline-block" />
            Empresas <span className="text-indigo-400 not-italic font-medium text-xl ml-2 tracking-widest">Fleet Control</span>
          </h1>
          <p className="text-slate-500 text-xs font-black uppercase tracking-[0.3em] ml-5">
            Gestión Global de Clientes y Folios Activos
          </p>
        </div>

        <button
          onClick={() => setShowModal(true)}
          className="premium-button flex items-center gap-3 px-8 group"
        >
          <span className="text-lg group-hover:rotate-90 transition-transform inline-block">+</span>
          ALTA DE NUEVA EMPRESA
        </button>
      </header>

      {/* Grid de Stats Rápidos (Opcional, añade mucha vista) */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
        <div className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
           <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Total Clientes</p>
           <p className="text-3xl font-black text-white">{companies.length}</p>
        </div>
        <div className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
           <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Folios Desplegados</p>
           <p className="text-3xl font-black text-indigo-400">
             {companies.reduce((acc, curr) => acc + curr.used_folios_count, 0)}
           </p>
        </div>
        <div className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
           <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Status Sistema</p>
           <div className="flex items-center gap-2">
             <div className="w-2 h-2 bg-emerald-500 rounded-full animate-pulse shadow-[0_0_8px_rgba(16,185,129,0.8)]" />
             <p className="text-xl font-black text-emerald-400 uppercase tracking-tighter italic">Operational</p>
           </div>
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center items-center h-64">
          <div className="w-12 h-12 border-4 border-indigo-500/20 border-t-indigo-500 rounded-full animate-spin" />
        </div>
      ) : (
        <div className="glass-card rounded-[2.5rem] overflow-hidden border-white/5">
          <table className="w-full text-left">
            <thead>
              <tr className="bg-white/[0.02] border-b border-white/5">
                <th className="px-8 py-6 text-[10px] font-black text-slate-500 uppercase tracking-widest">Identidad Corporativa</th>
                <th className="px-8 py-6 text-[10px] font-black text-slate-500 uppercase tracking-widest">Canal de Acceso</th>
                <th className="px-8 py-6 text-[10px] font-black text-slate-500 uppercase tracking-widest">Consumo de Folios</th>
                <th className="px-8 py-6 text-[10px] font-black text-slate-500 uppercase tracking-widest">Estado Vital</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/[0.02]">
              {companies.map((company) => (
                <tr key={company.id} className="hover:bg-white/[0.03] transition-colors group">
                  <td className="px-8 py-6">
                    <div className="flex items-center gap-4">
                      <div className="w-10 h-10 rounded-2xl bg-indigo-600/20 border border-indigo-500/30 flex items-center justify-center font-black text-indigo-400 italic">
                        {company.name[0]}
                      </div>
                      <span className="text-sm font-bold text-white group-hover:text-indigo-400 transition-colors">{company.name}</span>
                    </div>
                  </td>
                  <td className="px-8 py-6 text-xs font-medium text-slate-400">{company.primary_email}</td>
                  <td className="px-8 py-6">
                    <div className="flex items-center gap-3">
                      <div className="flex-1 h-1.5 bg-slate-800 rounded-full max-w-[100px] overflow-hidden">
                        <div
                          className="h-full bg-indigo-500 shadow-[0_0_10px_rgba(99,102,241,0.5)]"
                          style={{ width: `${(company.used_folios_count / company.total_folios_contracted) * 100}%` }}
                        />
                      </div>
                      <span className="text-xs font-black text-white">{company.used_folios_count}</span>
                      <span className="text-[10px] text-slate-600 font-bold">/ {company.total_folios_contracted}</span>
                    </div>
                  </td>
                  <td className="px-8 py-6">
                    <span className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-wider ${
                      company.status === 'active'
                      ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
                      : 'bg-red-500/10 text-red-400 border border-red-500/20'
                    }`}>
                      <span className={`w-1.5 h-1.5 rounded-full ${company.status === 'active' ? 'bg-emerald-400 animate-pulse' : 'bg-red-400'}`} />
                      {company.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Modal Glassmorphism */}
      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-6 backdrop-blur-md bg-black/40">
          <div className="glass-card rounded-[3rem] p-10 max-w-md w-full border-white/10 shadow-[0_0_50px_rgba(0,0,0,0.5)] animate-in fade-in zoom-in duration-300">
            <h2 className="text-2xl font-black text-white mb-8 italic uppercase tracking-tight">Registro de Nueva Terminal</h2>

            <form onSubmit={handleCreate} className="space-y-6">
              <div className="space-y-2">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Nombre Comercial</label>
                <input
                  type="text" required
                  className="premium-input w-full"
                  placeholder="Ej. Security Global SA"
                  value={formData.name}
                  onChange={e => setFormData({...formData, name: e.target.value})}
                />
              </div>
              <div className="space-y-2">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Email Operativo</label>
                <input
                  type="email" required
                  className="premium-input w-full"
                  placeholder="contact@company.com"
                  value={formData.primary_email}
                  onChange={e => setFormData({...formData, primary_email: e.target.value})}
                />
              </div>
              <div className="space-y-2">
                <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-4">Folios Iniciales</label>
                <input
                  type="number" required
                  className="premium-input w-full"
                  value={formData.total_folios_contracted}
                  onChange={e => setFormData({...formData, total_folios_contracted: parseInt(e.target.value)})}
                />
              </div>

              <div className="flex gap-4 pt-6">
                <button
                  type="button"
                  onClick={() => setShowModal(false)}
                  className="flex-1 py-4 bg-white/5 hover:bg-white/10 text-slate-400 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all"
                >
                  Cancelar
                </button>
                <button
                  type="submit"
                  className="flex-1 premium-button"
                >
                  CONFIRMAR ALTA
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
