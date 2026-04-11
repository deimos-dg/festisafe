'use client';

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';

export default function EditCompanyPage() {
  const { id } = useParams();
  const router = useRouter();

  // Estado local simulado (Se conectará al backend)
  const [company, setCompany] = useState({
    name: "FestiSafe Client A",
    limit: 100,
    used: 45,
    status: "active",
    email: "admin@clienta.com"
  });

  const handleSave = () => {
    alert("Plan actualizado con éxito");
    router.push('/admin/companies');
  };

  return (
    <div className="max-w-4xl mx-auto p-8">
      <div className="flex items-center gap-4 mb-8">
        <button onClick={() => router.back()} className="p-2 hover:bg-gray-100 rounded-full">←</button>
        <h1 className="text-3xl font-extrabold text-festisafe-primary">Configurar Plan de Empresa</h1>
      </div>

      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="p-8 space-y-6">
          <div className="grid grid-cols-2 gap-8">
            <div>
              <label className="block text-sm font-bold text-gray-500 mb-2 uppercase">Nombre de la Empresa</label>
              <input
                type="text"
                value={company.name}
                disabled
                className="w-full p-3 bg-gray-50 border border-gray-200 rounded-xl text-gray-400"
              />
            </div>
            <div>
              <label className="block text-sm font-bold text-gray-500 mb-2 uppercase">Email Principal</label>
              <input
                type="text"
                value={company.email}
                disabled
                className="w-full p-3 bg-gray-50 border border-gray-200 rounded-xl text-gray-400"
              />
            </div>
          </div>

          <div className="p-6 bg-blue-50 rounded-2xl border border-blue-100">
            <h3 className="font-bold text-blue-900 mb-4">Gestión de Folios (B2B)</h3>
            <div className="flex items-end gap-4">
              <div className="flex-1">
                <label className="block text-xs font-bold text-blue-600 mb-1 uppercase">Límite Total de Folios</label>
                <input
                  type="number"
                  value={company.limit}
                  onChange={(e) => setCompany({...company, limit: parseInt(e.target.value)})}
                  className="w-full p-3 bg-white border border-blue-200 rounded-xl focus:ring-2 focus:ring-festisafe-primary outline-none"
                />
              </div>
              <div className="bg-white px-6 py-3 rounded-xl border border-blue-200">
                <p className="text-xs text-gray-400 uppercase font-bold">Usados</p>
                <p className="text-xl font-black text-festisafe-primary">{company.used} / {company.limit}</p>
              </div>
            </div>
            <p className="mt-2 text-xs text-blue-400">Este límite define cuántos empleados puede cargar la empresa vía CSV.</p>
          </div>

          <div>
            <label className="block text-sm font-bold text-gray-500 mb-2 uppercase">Estado de la Empresa</label>
            <select
              value={company.status}
              onChange={(e) => setCompany({...company, status: e.target.value})}
              className="w-full p-3 border border-gray-200 rounded-xl outline-none"
            >
              <option value="active">🟢 Activa (Acceso total)</option>
              <option value="suspended">🔴 Suspendida (No puede generar folios)</option>
              <option value="pending">🟡 Pendiente de Pago</option>
            </select>
          </div>
        </div>

        <div className="bg-gray-50 p-6 flex justify-end gap-4">
          <button
            onClick={() => router.back()}
            className="px-6 py-2 text-gray-500 font-bold hover:text-gray-700"
          >
            Cancelar
          </button>
          <button
            onClick={handleSave}
            className="px-8 py-3 bg-festisafe-primary text-white font-bold rounded-xl hover:bg-opacity-90 transition-all shadow-lg"
          >
            Guardar Cambios
          </button>
        </div>
      </div>
    </div>
  );
}
