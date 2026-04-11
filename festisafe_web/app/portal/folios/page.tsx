'use client';

import { useState } from 'react';

export default function FoliosManagementPage() {
  const [folios, setFolios] = useState<any[]>([]);
  const [isUploading, setIsUploading] = useState(false);

  // Simulación de carga de CSV con estilo futurista
  const handleCSVUpload = (e: any) => {
    setIsUploading(true);
    setTimeout(() => {
      const mockFolios = [
        { code: 'FS-A1B2-C3D4', name: 'JUAN PÉREZ', role: 'SEGURIDAD TÁCTICA', status: 'DISPONIBLE' },
        { code: 'FS-X9Y8-Z7W6', name: 'MARÍA LÓPEZ', role: 'UNIDAD MÉDICA', status: 'CANJEADO' },
        { code: 'FS-P5R4-Q3S2', name: 'CARLOS RUIZ', role: 'LOGÍSTICA EVENTO', status: 'DISPONIBLE' },
      ];
      setFolios(mockFolios);
      setIsUploading(false);
    }, 1500);
  };

  const handleExport = () => {
    // Usamos el origen actual del navegador para que no se vea la URL de Railway directamente
    const baseUrl = window.location.origin.replace('3000', '8000'); // Ajuste para local vs prod
    window.open(`${baseUrl}/api/v1/companies/MY_ID/folios/export`, '_blank');
  };

  return (
    <div className="relative min-h-screen p-8 lg:p-12">

      {/* Header Sección */}
      <header className="flex flex-col md:flex-row justify-between items-start md:items-center mb-12 gap-6">
        <div className="space-y-1">
          <h1 className="text-4xl font-black text-white tracking-tight flex items-center gap-3 italic uppercase">
            <span className="w-2 h-8 bg-indigo-500 rounded-full inline-block" />
            Gestión de <span className="text-indigo-400 not-italic font-medium text-xl ml-2 tracking-widest">Folios & Personal</span>
          </h1>
          <p className="text-slate-500 text-xs font-black uppercase tracking-[0.3em] ml-5">
            Carga de Operativos y Generación de Credenciales Digitales
          </p>
        </div>

        <div className="flex gap-4">
          <button
            onClick={handleExport}
            className="px-8 py-4 bg-white/5 hover:bg-white/10 border border-white/10 text-slate-300 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all active:scale-95"
          >
            📊 EXPORTAR BASE DE DATOS
          </button>

          <label className="premium-button flex items-center gap-3 px-8 group cursor-pointer relative overflow-hidden">
             <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/10 to-transparent -translate-x-full group-hover:translate-x-full transition-transform duration-1000" />
             <span className="text-lg group-hover:rotate-12 transition-transform inline-block">↑</span>
             <span>{isUploading ? 'PROCESANDO...' : 'CARGAR CSV OPERATIVO'}</span>
             <input type="file" className="hidden" accept=".csv" onChange={handleCSVUpload} disabled={isUploading} />
          </label>
        </div>
      </header>

      {/* Grid de Stats de Folios */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-12">
        {[
          { label: 'Total Personal', val: folios.length, color: 'text-white' },
          { label: 'Folios Canjeados', val: folios.filter(f => f.status === 'CANJEADO').length, color: 'text-emerald-400' },
          { label: 'Disponibles', val: folios.filter(f => f.status === 'DISPONIBLE').length, color: 'text-indigo-400' },
          { label: 'Alerta Stock', val: '95%', color: 'text-amber-400' }
        ].map((stat, i) => (
          <div key={i} className="glass-card p-6 rounded-[2rem] border-white/5 bg-white/5">
             <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">{stat.label}</p>
             <p className={`text-3xl font-black ${stat.color}`}>{stat.val}</p>
          </div>
        ))}
      </div>

      {/* Tabla de Folios Futurista */}
      <div className="glass-card rounded-[2.5rem] overflow-hidden border-white/5">
        <table className="w-full text-left">
          <thead>
            <tr className="bg-white/[0.02] border-b border-white/5">
              <th className="px-8 py-6 text-[10px] font-black text-slate-500 uppercase tracking-widest">Código de Acceso</th>
              <th className="px-8 py-6 text-[10px] font-black text-slate-500 uppercase tracking-widest">Personal Asignado</th>
              <th className="px-8 py-6 text-[10px] font-black text-slate-500 uppercase tracking-widest">Rol Táctico</th>
              <th className="px-8 py-6 text-[10px] font-black text-slate-500 uppercase tracking-widest">Estado Credencial</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/[0.02]">
            {folios.length === 0 ? (
              <tr>
                <td colSpan={4} className="px-8 py-24 text-center">
                  <div className="flex flex-col items-center gap-4 opacity-30">
                    <div className="w-16 h-16 border-2 border-dashed border-slate-500 rounded-full flex items-center justify-center text-3xl font-light">+</div>
                    <p className="text-xs font-black uppercase tracking-[0.4em]">Sin Datos - Requiere Carga CSV</p>
                  </div>
                </td>
              </tr>
            ) : (
              folios.map((f, i) => (
                <tr key={i} className="hover:bg-white/[0.03] transition-colors group">
                  <td className="px-8 py-6">
                    <div className="flex items-center gap-3">
                      <div className="w-2 h-2 bg-indigo-500 rounded-full shadow-[0_0_8px_rgba(99,102,241,0.5)]" />
                      <span className="text-sm font-mono font-black text-indigo-300 tracking-wider group-hover:text-white transition-colors">
                        {f.code}
                      </span>
                    </div>
                  </td>
                  <td className="px-8 py-6">
                    <span className="text-xs font-bold text-white uppercase tracking-tighter">{f.name}</span>
                  </td>
                  <td className="px-8 py-6">
                    <span className="text-[10px] font-black text-slate-400 tracking-widest border border-slate-800 px-3 py-1 rounded-lg bg-slate-900/50">
                      {f.role}
                    </span>
                  </td>
                  <td className="px-8 py-6">
                    <span className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-wider ${
                      f.status === 'CANJEADO'
                      ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
                      : 'bg-indigo-500/10 text-indigo-400 border border-indigo-500/20'
                    }`}>
                      <span className={`w-1.5 h-1.5 rounded-full ${f.status === 'CANJEADO' ? 'bg-emerald-400' : 'bg-indigo-400 animate-pulse'}`} />
                      {f.status}
                    </span>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Instrucciones de Carga */}
      <footer className="mt-8 px-6 py-4 glass-card rounded-2xl border-indigo-500/10 bg-indigo-500/5 inline-flex items-center gap-4">
        <span className="text-indigo-400 text-lg">ℹ</span>
        <p className="text-[10px] font-bold text-slate-400 uppercase tracking-widest leading-relaxed">
          Asegúrate que el archivo CSV tenga las columnas: <span className="text-white underline">name, role</span>. El sistema generará los códigos únicos automáticamente.
        </p>
      </footer>
    </div>
  );
}
