'use client';

import { useState, useEffect, useCallback } from 'react';
import { fetchWithAuth, adminApi } from '@/lib/api';

interface Company {
  id: string;
  name: string;
  total_folios_contracted: number;
  used_folios_count: number;
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

interface ParsedRow {
  employee_name: string;
  employee_role: string;
  employee_phone?: string;
}

export default function FoliosManagementPage() {
  const [companies, setCompanies] = useState<Company[]>([]);
  const [selectedCompany, setSelectedCompany] = useState<Company | null>(null);
  const [folios, setFolios] = useState<Folio[]>([]);
  const [loadingFolios, setLoadingFolios] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [uploadPreview, setUploadPreview] = useState<ParsedRow[]>([]);
  const [uploadError, setUploadError] = useState('');
  const [showUploadModal, setShowUploadModal] = useState(false);
  const [search, setSearch] = useState('');
  const [filterStatus, setFilterStatus] = useState<'all' | 'used' | 'available'>('all');

  useEffect(() => {
    adminApi.getCompanies().then(setCompanies).catch(console.error);
  }, []);

  const loadFolios = useCallback(async (company: Company) => {
    setLoadingFolios(true);
    try {
      const data = await fetchWithAuth(`/companies/${company.id}/folios`);
      setFolios(Array.isArray(data) ? data : []);
    } catch (e) {
      console.error(e);
    } finally {
      setLoadingFolios(false);
    }
  }, []);

  function selectCompany(company: Company) {
    setSelectedCompany(company);
    setFolios([]);
    setSearch('');
    setFilterStatus('all');
    loadFolios(company);
  }

  // ── Parsear CSV ────────────────────────────────────────────────────────────
  function parseCSV(text: string): ParsedRow[] {
    const lines = text.trim().split('\n').filter(l => l.trim());
    if (lines.length < 2) throw new Error('El CSV debe tener encabezado y al menos una fila');

    const headers = lines[0].split(',').map(h => h.trim().toLowerCase().replace(/['"]/g, ''));
    const nameIdx = headers.findIndex(h => h.includes('name') || h.includes('nombre'));
    const roleIdx = headers.findIndex(h => h.includes('role') || h.includes('rol') || h.includes('puesto'));
    const phoneIdx = headers.findIndex(h => h.includes('phone') || h.includes('tel') || h.includes('celular'));

    if (nameIdx === -1) throw new Error('El CSV debe tener una columna "name" o "nombre"');
    if (roleIdx === -1) throw new Error('El CSV debe tener una columna "role", "rol" o "puesto"');

    return lines.slice(1).map(line => {
      const cols = line.split(',').map(c => c.trim().replace(/['"]/g, ''));
      return {
        employee_name: cols[nameIdx] || '',
        employee_role: cols[roleIdx] || '',
        employee_phone: phoneIdx >= 0 ? cols[phoneIdx] : undefined,
      };
    }).filter(r => r.employee_name);
  }

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadError('');
    const reader = new FileReader();
    reader.onload = (ev) => {
      try {
        const rows = parseCSV(ev.target?.result as string);
        if (rows.length === 0) throw new Error('No se encontraron filas válidas');
        setUploadPreview(rows);
        setShowUploadModal(true);
      } catch (err: unknown) {
        setUploadError(err instanceof Error ? err.message : 'Error al leer el CSV');
      }
    };
    reader.readAsText(file);
    e.target.value = '';
  }

  async function confirmUpload() {
    if (!selectedCompany || uploadPreview.length === 0) return;
    setIsUploading(true);
    try {
      await fetchWithAuth(`/companies/${selectedCompany.id}/folios/bulk`, {
        method: 'POST',
        body: JSON.stringify({ folios: uploadPreview }),
      });
      setShowUploadModal(false);
      setUploadPreview([]);
      await loadFolios(selectedCompany);
      // Refrescar contador de la empresa
      const updated = await adminApi.getCompanies();
      setCompanies(updated);
      const refreshed = updated.find((c: Company) => c.id === selectedCompany.id);
      if (refreshed) setSelectedCompany(refreshed);
    } catch (err: unknown) {
      setUploadError(err instanceof Error ? err.message : 'Error al generar folios');
    } finally {
      setIsUploading(false);
    }
  }

  function handleExport() {
    if (!selectedCompany) return;
    const apiBase = process.env.NEXT_PUBLIC_API_URL || 'https://festisafe-production.up.railway.app';
    window.open(`${apiBase}/api/v1/companies/${selectedCompany.id}/folios/export`, '_blank');
  }

  const filtered = folios.filter(f => {
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

  const available = folios.filter(f => !f.is_used).length;
  const used = folios.filter(f => f.is_used).length;
  const capacity = selectedCompany
    ? selectedCompany.total_folios_contracted - selectedCompany.used_folios_count
    : 0;

  return (
    <div className="relative min-h-screen p-8 lg:p-12">
      <header className="flex flex-col md:flex-row justify-between items-start md:items-center mb-10 gap-6">
        <div className="space-y-1">
          <h1 className="text-4xl font-black text-white tracking-tight flex items-center gap-3 italic uppercase">
            <span className="w-2 h-8 bg-indigo-500 rounded-full inline-block" />
            Folios <span className="text-indigo-400 not-italic font-medium text-xl ml-2 tracking-widest">& Personal</span>
          </h1>
          <p className="text-slate-500 text-xs font-black uppercase tracking-[0.3em] ml-5">
            Credenciales digitales por empresa
          </p>
        </div>

        {selectedCompany && (
          <div className="flex gap-3">
            <button onClick={handleExport}
              className="px-6 py-3 bg-white/5 hover:bg-white/10 border border-white/10 text-slate-300 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">
              📊 Exportar Excel
            </button>
            <label className="premium-button flex items-center gap-2 px-6 cursor-pointer">
              <span>↑</span>
              <span>{isUploading ? 'Procesando...' : 'Cargar CSV'}</span>
              <input type="file" className="hidden" accept=".csv,.txt" onChange={handleFileChange} disabled={isUploading} />
            </label>
          </div>
        )}
      </header>

      {uploadError && (
        <div className="mb-6 bg-red-500/10 border border-red-500/20 text-red-400 p-4 rounded-2xl text-xs font-bold">
          ⚠️ {uploadError}
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
        {/* Selector de empresa */}
        <div className="lg:col-span-1">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-3">Empresa</p>
          <div className="space-y-2">
            {companies.map(c => (
              <button key={c.id} onClick={() => selectCompany(c)}
                className={`w-full text-left p-4 rounded-2xl border transition-all ${
                  selectedCompany?.id === c.id
                    ? 'bg-indigo-600/20 border-indigo-500/40 text-white'
                    : 'bg-white/[0.03] border-white/5 text-slate-400 hover:bg-white/[0.06] hover:text-white'
                }`}>
                <p className="text-sm font-bold truncate">{c.name}</p>
                <p className="text-[10px] text-slate-500 mt-0.5">
                  {c.used_folios_count}/{c.total_folios_contracted} folios
                </p>
              </button>
            ))}
            {companies.length === 0 && (
              <p className="text-xs text-slate-600 text-center py-4">Sin empresas registradas</p>
            )}
          </div>
        </div>

        {/* Panel de folios */}
        <div className="lg:col-span-3">
          {!selectedCompany ? (
            <div className="glass-card rounded-[2.5rem] p-16 text-center border-white/5 bg-white/5 h-64 flex flex-col items-center justify-center">
              <p className="text-3xl mb-3">📋</p>
              <p className="text-slate-500 text-xs font-black uppercase tracking-widest">Selecciona una empresa</p>
            </div>
          ) : (
            <>
              {/* Stats */}
              <div className="grid grid-cols-4 gap-4 mb-6">
                {[
                  { label: 'Total', val: folios.length, color: 'text-white' },
                  { label: 'Disponibles', val: available, color: 'text-indigo-400' },
                  { label: 'Canjeados', val: used, color: 'text-emerald-400' },
                  { label: 'Cupo libre', val: capacity, color: capacity > 0 ? 'text-amber-400' : 'text-red-400' },
                ].map((s, i) => (
                  <div key={i} className="glass-card p-4 rounded-2xl border-white/5 bg-white/5 text-center">
                    <p className="text-[9px] font-black text-slate-500 uppercase tracking-widest mb-1">{s.label}</p>
                    <p className={`text-2xl font-black ${s.color}`}>{s.val}</p>
                  </div>
                ))}
              </div>

              {/* Filtros */}
              <div className="flex gap-3 mb-4 flex-wrap">
                <input type="text" placeholder="Buscar código, nombre o rol..."
                  value={search} onChange={e => setSearch(e.target.value)}
                  className="flex-1 min-w-[200px] bg-white/[0.05] border border-white/10 rounded-xl px-4 py-2 text-xs text-white outline-none focus:border-indigo-500 transition-all" />
                {(['all', 'available', 'used'] as const).map(f => (
                  <button key={f} onClick={() => setFilterStatus(f)}
                    className={`px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all border ${
                      filterStatus === f
                        ? 'bg-indigo-600 text-white border-indigo-500'
                        : 'bg-white/5 text-slate-400 border-white/10 hover:bg-white/10'
                    }`}>
                    {f === 'all' ? 'Todos' : f === 'available' ? 'Disponibles' : 'Canjeados'}
                  </button>
                ))}
              </div>

              {/* Tabla */}
              {loadingFolios ? (
                <div className="flex justify-center py-16">
                  <div className="w-10 h-10 border-4 border-indigo-500/20 border-t-indigo-500 rounded-full animate-spin" />
                </div>
              ) : (
                <div className="glass-card rounded-[2rem] overflow-hidden border-white/5">
                  <table className="w-full text-left">
                    <thead>
                      <tr className="bg-white/[0.02] border-b border-white/5">
                        <th className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">Código</th>
                        <th className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">Empleado</th>
                        <th className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">Rol</th>
                        <th className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">Estado</th>
                        <th className="px-6 py-4 text-[10px] font-black text-slate-500 uppercase tracking-widest">Fecha</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-white/[0.02]">
                      {filtered.length === 0 ? (
                        <tr>
                          <td colSpan={5} className="px-6 py-16 text-center text-slate-600 text-xs font-black uppercase tracking-widest">
                            {folios.length === 0 ? 'Sin folios — carga un CSV para generar' : 'Sin resultados'}
                          </td>
                        </tr>
                      ) : filtered.map(f => (
                        <tr key={f.id} className="hover:bg-white/[0.03] transition-colors">
                          <td className="px-6 py-4">
                            <span className="text-sm font-mono font-black text-indigo-300 tracking-wider">{f.code}</span>
                          </td>
                          <td className="px-6 py-4 text-xs font-bold text-white">{f.employee_name || '—'}</td>
                          <td className="px-6 py-4">
                            <span className="text-[10px] font-black text-slate-400 border border-slate-800 px-2 py-1 rounded-lg bg-slate-900/50">
                              {f.employee_role || '—'}
                            </span>
                          </td>
                          <td className="px-6 py-4">
                            <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-xl text-[10px] font-black uppercase tracking-wider border ${
                              f.is_used
                                ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20'
                                : 'bg-indigo-500/10 text-indigo-400 border-indigo-500/20'
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
              )}
            </>
          )}
        </div>
      </div>

      {/* Modal: Preview de carga CSV */}
      {showUploadModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-6 backdrop-blur-md bg-black/50">
          <div className="glass-card rounded-[2.5rem] p-8 max-w-2xl w-full border-white/10 shadow-[0_0_60px_rgba(0,0,0,0.6)] max-h-[80vh] flex flex-col">
            <div className="flex items-center justify-between mb-6">
              <div>
                <h2 className="text-xl font-black text-white italic uppercase tracking-tight">Confirmar Carga</h2>
                <p className="text-slate-500 text-xs mt-1">{uploadPreview.length} empleados · {selectedCompany?.name}</p>
              </div>
              <button onClick={() => { setShowUploadModal(false); setUploadPreview([]); }}
                className="text-slate-500 hover:text-white text-lg transition-all">✕</button>
            </div>

            {uploadError && (
              <div className="mb-4 bg-red-500/10 border border-red-500/20 text-red-400 p-3 rounded-xl text-xs font-bold">
                ⚠️ {uploadError}
              </div>
            )}

            {/* Verificar cupo */}
            {capacity < uploadPreview.length && (
              <div className="mb-4 bg-amber-500/10 border border-amber-500/20 text-amber-400 p-3 rounded-xl text-xs font-bold">
                ⚠️ Cupo insuficiente: tienes {capacity} folios disponibles pero el CSV tiene {uploadPreview.length} filas.
              </div>
            )}

            <div className="overflow-y-auto flex-1 mb-6">
              <table className="w-full text-left">
                <thead className="sticky top-0 bg-slate-900">
                  <tr className="border-b border-white/5">
                    <th className="py-2 px-3 text-[10px] font-black text-slate-500 uppercase tracking-widest">#</th>
                    <th className="py-2 px-3 text-[10px] font-black text-slate-500 uppercase tracking-widest">Nombre</th>
                    <th className="py-2 px-3 text-[10px] font-black text-slate-500 uppercase tracking-widest">Rol</th>
                    <th className="py-2 px-3 text-[10px] font-black text-slate-500 uppercase tracking-widest">Teléfono</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/[0.02]">
                  {uploadPreview.map((row, i) => (
                    <tr key={i} className="hover:bg-white/[0.02]">
                      <td className="py-2 px-3 text-[10px] text-slate-600">{i + 1}</td>
                      <td className="py-2 px-3 text-xs text-white font-bold">{row.employee_name}</td>
                      <td className="py-2 px-3 text-xs text-slate-400">{row.employee_role}</td>
                      <td className="py-2 px-3 text-xs text-slate-500">{row.employee_phone || '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="flex gap-4">
              <button onClick={() => { setShowUploadModal(false); setUploadPreview([]); setUploadError(''); }}
                className="flex-1 py-3 bg-white/5 hover:bg-white/10 text-slate-400 rounded-2xl font-black text-[10px] uppercase tracking-widest transition-all">
                Cancelar
              </button>
              <button onClick={confirmUpload}
                disabled={isUploading || capacity < uploadPreview.length}
                className="flex-1 premium-button">
                {isUploading ? 'Generando folios...' : `GENERAR ${uploadPreview.length} FOLIOS`}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Instrucciones */}
      <div className="mt-8 px-6 py-4 glass-card rounded-2xl border-indigo-500/10 bg-indigo-500/5 inline-flex items-start gap-4">
        <span className="text-indigo-400 text-lg mt-0.5">ℹ</span>
        <div>
          <p className="text-[10px] font-bold text-slate-400 uppercase tracking-widest leading-relaxed">
            Columnas requeridas en el CSV: <span className="text-white">name</span> (o nombre) y <span className="text-white">role</span> (o rol/puesto).
            Columna opcional: <span className="text-white">phone</span> (o tel/celular).
          </p>
          <p className="text-[10px] text-slate-600 mt-1">
            Ejemplo: <span className="font-mono text-slate-500">name,role,phone</span>
          </p>
        </div>
      </div>
    </div>
  );
}
