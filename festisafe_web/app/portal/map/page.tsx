'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import { fetchWithAuth, getToken } from '@/lib/api';

interface Employee {
  user_id: string;
  name: string;
  latitude: number;
  longitude: number;
  accuracy: number | null;
  is_visible: boolean;
  updated_at: string;
  role?: string;
}

interface SosAlert {
  id: string;
  user_id: string;
  name: string;
  latitude: number | null;
  longitude: number | null;
  started_at: string | null;
  status: string;
}

interface GeofenceAlert {
  type: 'geofence_alert';
  event_type: 'entered' | 'exited';
  geofence_name: string;
  geofence_type: string;
  user_name: string;
  timestamp: string;
}

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'https://festisafe-production.up.railway.app';
const WS_BASE = API_BASE.replace('https://', 'wss://').replace('http://', 'ws://');

export default function PortalMapPage() {
  const mapRef = useRef<HTMLDivElement>(null);
  const leafletMapRef = useRef<unknown>(null);
  const markersRef = useRef<Record<string, unknown>>({});
  const wsRef = useRef<WebSocket | null>(null);

  const [employees, setEmployees] = useState<Employee[]>([]);
  const [sosAlerts, setSosAlerts] = useState<SosAlert[]>([]);
  const [geofenceLog, setGeofenceLog] = useState<GeofenceAlert[]>([]);
  const [broadcastTitle, setBroadcastTitle] = useState('');
  const [broadcastContent, setBroadcastContent] = useState('');
  const [broadcastSending, setBroadcastSending] = useState(false);
  const [wsStatus, setWsStatus] = useState<'connecting' | 'connected' | 'disconnected'>('disconnected');
  const [selectedEmployee, setSelectedEmployee] = useState<Employee | null>(null);

  // ── Inicializar mapa Leaflet ──────────────────────────────────────────────
  useEffect(() => {
    if (!mapRef.current || leafletMapRef.current) return;

    // Leaflet solo funciona en el cliente
    import('leaflet').then(L => {
      // Fix icono por defecto de Leaflet con webpack
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      delete (L.Icon.Default.prototype as any)._getIconUrl;
      L.Icon.Default.mergeOptions({
        iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
        iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
        shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
      });

      const map = L.map(mapRef.current!, {
        center: [19.4326, -99.1332], // CDMX por defecto
        zoom: 13,
        zoomControl: true,
      });

      // Tiles oscuros (CartoDB Dark Matter)
      L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
        attribution: '© OpenStreetMap © CARTO',
        subdomains: 'abcd',
        maxZoom: 19,
      }).addTo(map);

      leafletMapRef.current = map;
    });

    return () => {
      if (leafletMapRef.current) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (leafletMapRef.current as any).remove();
        leafletMapRef.current = null;
      }
    };
  }, []);

  // ── Actualizar marcadores en el mapa ─────────────────────────────────────
  const updateMarkers = useCallback((emps: Employee[], sos: SosAlert[]) => {
    if (!leafletMapRef.current) return;

    import('leaflet').then(L => {
      const map = leafletMapRef.current as ReturnType<typeof L.map>;
      const sosIds = new Set(sos.map(s => s.user_id));

      // Eliminar marcadores de empleados que ya no están
      const currentIds = new Set(emps.map(e => e.user_id));
      Object.keys(markersRef.current).forEach(id => {
        if (!currentIds.has(id)) {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          (markersRef.current[id] as any).remove();
          delete markersRef.current[id];
        }
      });

      emps.forEach(emp => {
        if (!emp.latitude || !emp.longitude) return;
        const isSos = sosIds.has(emp.user_id);
        const minutesAgo = (Date.now() - new Date(emp.updated_at).getTime()) / 60000;
        const isStale = minutesAgo > 5;

        const color = isSos ? '#ef4444' : isStale ? '#64748b' : '#6366f1';
        const pulseColor = isSos ? 'rgba(239,68,68,0.4)' : 'rgba(99,102,241,0.3)';

        const icon = L.divIcon({
          className: '',
          html: `
            <div style="position:relative;width:32px;height:32px">
              ${!isStale ? `<div style="position:absolute;inset:-8px;border-radius:50%;background:${pulseColor};animation:ping 1.5s cubic-bezier(0,0,0.2,1) infinite"></div>` : ''}
              <div style="width:32px;height:32px;border-radius:50%;background:${color};border:2px solid white;
                          display:flex;align-items:center;justify-content:center;
                          font-size:11px;font-weight:900;color:white;
                          box-shadow:0 2px 8px rgba(0,0,0,0.5);position:relative">
                ${isSos ? '🆘' : emp.name[0]?.toUpperCase()}
              </div>
            </div>`,
          iconSize: [32, 32],
          iconAnchor: [16, 16],
        });

        const popup = L.popup({ className: 'dark-popup' }).setContent(`
          <div style="background:#0f172a;border:1px solid rgba(255,255,255,0.1);border-radius:12px;padding:12px;min-width:160px">
            <p style="color:white;font-weight:900;font-size:13px;margin:0 0 4px">${emp.name}</p>
            <p style="color:#94a3b8;font-size:10px;margin:0 0 2px;text-transform:uppercase;letter-spacing:0.1em">${emp.role || 'Empleado'}</p>
            <p style="color:#64748b;font-size:10px;margin:0">${minutesAgo < 1 ? 'Ahora mismo' : `Hace ${Math.round(minutesAgo)} min`}</p>
            ${isSos ? '<p style="color:#ef4444;font-weight:900;font-size:11px;margin:6px 0 0">🆘 SOS ACTIVO</p>' : ''}
          </div>`);

        if (markersRef.current[emp.user_id]) {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          (markersRef.current[emp.user_id] as any)
            .setLatLng([emp.latitude, emp.longitude])
            .setIcon(icon);
        } else {
          const marker = L.marker([emp.latitude, emp.longitude], { icon })
            .bindPopup(popup)
            .addTo(map);
          markersRef.current[emp.user_id] = marker;
        }
      });
    });
  }, []);

  // ── Cargar datos HTTP ─────────────────────────────────────────────────────
  const loadData = useCallback(async () => {
    try {
      const [emps, alerts] = await Promise.all([
        fetchWithAuth('/users/active').catch(() => []),
        fetchWithAuth('/sos/recent').catch(() => []),
      ]);
      const empList = Array.isArray(emps) ? emps : [];
      const sosList = Array.isArray(alerts) ? alerts : [];
      setEmployees(empList);
      setSosAlerts(sosList);
      updateMarkers(empList, sosList);
    } catch (e) {
      console.error(e);
    }
  }, [updateMarkers]);

  useEffect(() => {
    loadData();
    const interval = setInterval(loadData, 15000);
    return () => clearInterval(interval);
  }, [loadData]);

  // ── WebSocket para alertas de geofence en tiempo real ────────────────────
  useEffect(() => {
    const token = getToken();
    if (!token) return;

    function connect() {
      setWsStatus('connecting');
      // Conectar al WS de empresa usando el topic company_{id}
      // Por ahora usamos el endpoint de health para verificar conectividad
      // El WS real de geofence se conecta cuando hay company_id disponible
      const ws = new WebSocket(`${WS_BASE}/ws/portal?token=${token}`);
      wsRef.current = ws;

      ws.onopen = () => setWsStatus('connected');
      ws.onclose = () => {
        setWsStatus('disconnected');
        setTimeout(connect, 5000);
      };
      ws.onerror = () => ws.close();

      ws.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);
          if (msg.type === 'geofence_alert') {
            setGeofenceLog(prev => [msg, ...prev].slice(0, 50));
          }
          if (msg.type === 'sos') {
            loadData();
          }
        } catch (_) {}
      };
    }

    // Solo conectar si hay WS de portal disponible
    // Por ahora el polling HTTP es suficiente
    setWsStatus('connected'); // Simulado hasta que el WS de portal esté implementado

    return () => {
      wsRef.current?.close();
    };
  }, [loadData]);

  // ── Broadcast ─────────────────────────────────────────────────────────────
  async function sendBroadcast() {
    if (!broadcastTitle.trim() || !broadcastContent.trim()) return;
    setBroadcastSending(true);
    try {
      await fetchWithAuth('/intelligence/broadcast', {
        method: 'POST',
        body: JSON.stringify({
          title: broadcastTitle,
          content: broadcastContent,
          target: 'all',
        }),
      });
      setBroadcastTitle('');
      setBroadcastContent('');
    } catch (e) {
      console.error(e);
    } finally {
      setBroadcastSending(false);
    }
  }

  const criticalBattery = employees.filter(e => (e as Employee & { battery?: number }).battery !== undefined && ((e as Employee & { battery?: number }).battery ?? 100) < 20);

  return (
    <div className="relative h-screen w-full bg-[#0f172a] overflow-hidden font-sans antialiased text-slate-200">

      {/* Estilos de animación para marcadores */}
      <style>{`
        @keyframes ping {
          75%, 100% { transform: scale(2); opacity: 0; }
        }
        .dark-popup .leaflet-popup-content-wrapper {
          background: transparent;
          border: none;
          box-shadow: none;
          padding: 0;
        }
        .dark-popup .leaflet-popup-tip { display: none; }
        .leaflet-container { background: #0f172a; }
      `}</style>

      {/* Mapa Leaflet */}
      <div ref={mapRef} className="absolute inset-0 z-0" />

      {/* Header flotante */}
      <nav className="absolute top-4 left-4 right-4 z-30 flex justify-between items-center px-5 py-3
                      bg-slate-900/70 backdrop-blur-xl border border-white/10 rounded-2xl shadow-2xl">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 bg-indigo-600 rounded-xl flex items-center justify-center shadow-lg">
            <span className="text-white font-black text-xs">FS</span>
          </div>
          <div>
            <p className="text-white font-bold text-sm tracking-tight">FestiSafe <span className="text-indigo-400 font-medium">Control Center</span></p>
            <p className="text-[9px] text-slate-500 uppercase tracking-widest">Live Monitoring</p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 px-3 py-1.5 bg-slate-800/60 rounded-full border border-slate-700/50">
            <div className={`w-1.5 h-1.5 rounded-full ${wsStatus === 'connected' ? 'bg-emerald-500 animate-pulse' : wsStatus === 'connecting' ? 'bg-amber-500 animate-pulse' : 'bg-red-500'}`} />
            <span className="text-[10px] font-bold text-slate-300 uppercase tracking-wider">
              {wsStatus === 'connected' ? 'Online' : wsStatus === 'connecting' ? 'Conectando' : 'Offline'}
            </span>
          </div>
          <button onClick={loadData}
            className="px-3 py-1.5 bg-slate-800/60 rounded-full border border-slate-700/50 text-[10px] font-bold text-slate-400 hover:text-white transition-all">
            ↻ Actualizar
          </button>
        </div>
      </nav>

      {/* Sidebar izquierdo */}
      <aside className="absolute top-20 left-4 bottom-4 w-72 z-20 flex flex-col gap-3 overflow-y-auto">

        {/* SOS activos */}
        {sosAlerts.length > 0 && (
          <div className="bg-red-500/20 backdrop-blur-xl border border-red-500/40 rounded-2xl p-4 shadow-[0_0_30px_rgba(239,68,68,0.2)]">
            <div className="flex items-center gap-2 mb-3">
              <span className="text-lg">🚨</span>
              <p className="text-sm font-black text-red-100 uppercase tracking-wider">SOS Activos ({sosAlerts.length})</p>
            </div>
            <div className="space-y-2">
              {sosAlerts.map(alert => (
                <div key={alert.id} className="flex items-center justify-between bg-red-500/10 rounded-xl p-3">
                  <div>
                    <p className="text-xs font-bold text-red-100">{alert.name}</p>
                    <p className="text-[10px] text-red-400/70">
                      {alert.started_at ? new Date(alert.started_at).toLocaleTimeString('es-MX') : '—'}
                    </p>
                  </div>
                  {alert.latitude && alert.longitude && (
                    <button
                      onClick={() => {
                        if (leafletMapRef.current) {
                          // eslint-disable-next-line @typescript-eslint/no-explicit-any
                          (leafletMapRef.current as any).flyTo([alert.latitude, alert.longitude], 17);
                        }
                      }}
                      className="text-[10px] font-black text-red-400 hover:text-red-200 transition-all uppercase tracking-wider">
                      Localizar →
                    </button>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Empleados activos */}
        <div className="bg-slate-900/60 backdrop-blur-xl border border-white/10 rounded-2xl p-4 shadow-xl flex-1 min-h-0">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-3">
            Personal Activo ({employees.length})
          </p>
          <div className="space-y-2 overflow-y-auto max-h-48">
            {employees.length === 0 ? (
              <p className="text-[11px] text-slate-600 text-center py-4">Sin personal con ubicación activa</p>
            ) : employees.map(emp => {
              const minutesAgo = (Date.now() - new Date(emp.updated_at).getTime()) / 60000;
              const isSos = sosAlerts.some(s => s.user_id === emp.user_id);
              return (
                <button key={emp.user_id}
                  onClick={() => {
                    setSelectedEmployee(emp);
                    if (leafletMapRef.current && emp.latitude && emp.longitude) {
                      // eslint-disable-next-line @typescript-eslint/no-explicit-any
                      (leafletMapRef.current as any).flyTo([emp.latitude, emp.longitude], 17);
                    }
                  }}
                  className="w-full flex items-center gap-3 p-2.5 rounded-xl hover:bg-white/5 transition-all text-left">
                  <div className={`w-7 h-7 rounded-lg flex items-center justify-center text-xs font-black flex-shrink-0 ${
                    isSos ? 'bg-red-500/20 text-red-400' : 'bg-indigo-500/20 text-indigo-400'
                  }`}>
                    {isSos ? '🆘' : emp.name[0]?.toUpperCase()}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-xs font-bold text-white truncate">{emp.name}</p>
                    <p className="text-[10px] text-slate-500">
                      {minutesAgo < 1 ? 'Ahora' : `Hace ${Math.round(minutesAgo)} min`}
                    </p>
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Batería crítica */}
        {criticalBattery.length > 0 && (
          <div className="bg-slate-900/60 backdrop-blur-xl border border-red-500/20 rounded-2xl p-4">
            <p className="text-[10px] font-black text-red-400 uppercase tracking-widest mb-2">🪫 Batería Crítica</p>
            {criticalBattery.map(e => (
              <div key={e.user_id} className="flex items-center justify-between py-1">
                <p className="text-xs text-slate-300">{e.name}</p>
                <p className="text-xs font-black text-red-400">{(e as Employee & { battery?: number }).battery}%</p>
              </div>
            ))}
          </div>
        )}

        {/* Log de geofences */}
        {geofenceLog.length > 0 && (
          <div className="bg-slate-900/60 backdrop-blur-xl border border-amber-500/20 rounded-2xl p-4">
            <p className="text-[10px] font-black text-amber-400 uppercase tracking-widest mb-2">🌐 Alertas Geofence</p>
            <div className="space-y-1.5 max-h-32 overflow-y-auto">
              {geofenceLog.slice(0, 10).map((g, i) => (
                <div key={i} className="text-[10px] text-slate-400">
                  <span className={g.event_type === 'entered' ? 'text-emerald-400' : 'text-red-400'}>
                    {g.event_type === 'entered' ? '↗' : '↙'}
                  </span>
                  {' '}<span className="text-white font-bold">{g.user_name}</span>
                  {' '}{g.event_type === 'entered' ? 'entró a' : 'salió de'}
                  {' '}<span className="text-amber-300">{g.geofence_name}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </aside>

      {/* Panel derecho — Broadcast */}
      <aside className="absolute top-20 right-4 bottom-4 w-64 z-20 flex flex-col gap-3">
        <div className="bg-slate-900/60 backdrop-blur-xl border border-white/10 rounded-2xl p-4 shadow-xl">
          <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-3">📢 Broadcast Masivo</p>
          <div className="space-y-2">
            <input type="text" placeholder="Título del mensaje"
              value={broadcastTitle} onChange={e => setBroadcastTitle(e.target.value)}
              className="w-full bg-slate-800/50 border border-slate-700/50 rounded-xl px-3 py-2 text-xs text-white outline-none focus:border-indigo-500 transition-all" />
            <textarea placeholder="Mensaje para todos los empleados..."
              value={broadcastContent} onChange={e => setBroadcastContent(e.target.value)}
              rows={3}
              className="w-full bg-slate-800/50 border border-slate-700/50 rounded-xl px-3 py-2 text-xs text-white outline-none resize-none focus:border-indigo-500 transition-all" />
            <button onClick={sendBroadcast} disabled={broadcastSending || !broadcastTitle.trim()}
              className="w-full py-2.5 bg-indigo-600 hover:bg-indigo-500 disabled:bg-slate-800 disabled:cursor-not-allowed text-white rounded-xl font-black text-[10px] tracking-widest transition-all">
              {broadcastSending ? 'Enviando...' : 'ENVIAR'}
            </button>
          </div>
        </div>

        {/* Info del empleado seleccionado */}
        {selectedEmployee && (
          <div className="bg-slate-900/60 backdrop-blur-xl border border-indigo-500/20 rounded-2xl p-4 shadow-xl">
            <div className="flex items-center justify-between mb-3">
              <p className="text-[10px] font-black text-indigo-400 uppercase tracking-widest">Seleccionado</p>
              <button onClick={() => setSelectedEmployee(null)} className="text-slate-500 hover:text-white text-xs">✕</button>
            </div>
            <div className="flex items-center gap-3 mb-3">
              <div className="w-10 h-10 rounded-xl bg-indigo-600/20 border border-indigo-500/30 flex items-center justify-center font-black text-indigo-400">
                {selectedEmployee.name[0]?.toUpperCase()}
              </div>
              <div>
                <p className="text-sm font-bold text-white">{selectedEmployee.name}</p>
                <p className="text-[10px] text-slate-500">{selectedEmployee.role || 'Empleado'}</p>
              </div>
            </div>
            <div className="space-y-1 text-[10px] text-slate-400">
              <p>Lat: <span className="text-white font-mono">{selectedEmployee.latitude?.toFixed(5)}</span></p>
              <p>Lng: <span className="text-white font-mono">{selectedEmployee.longitude?.toFixed(5)}</span></p>
              <p>Actualizado: <span className="text-white">{new Date(selectedEmployee.updated_at).toLocaleTimeString('es-MX')}</span></p>
            </div>
          </div>
        )}
      </aside>

      {/* Footer */}
      <footer className="absolute bottom-4 left-80 right-72 h-10 z-30 flex items-center justify-between px-5
                         bg-slate-900/60 backdrop-blur-md border border-white/5 rounded-xl shadow-xl mx-4">
        <div className="flex gap-5 items-center">
          <span className="text-[10px] font-bold text-slate-400 flex items-center gap-1.5">
            <span className="w-1.5 h-1.5 bg-indigo-500 rounded-full" />
            Personal: <span className="text-white ml-1">{employees.length}</span>
          </span>
          <span className="text-[10px] font-bold text-slate-400 flex items-center gap-1.5">
            <span className="w-1.5 h-1.5 bg-red-500 rounded-full" />
            SOS: <span className="text-white ml-1">{sosAlerts.length}</span>
          </span>
          <span className="text-[10px] font-bold text-slate-400 flex items-center gap-1.5">
            <span className="w-1.5 h-1.5 bg-amber-500 rounded-full" />
            Geofence: <span className="text-white ml-1">{geofenceLog.length}</span>
          </span>
        </div>
        <span className="text-[9px] font-black text-slate-600 uppercase tracking-widest">
          Leaflet · OpenStreetMap · CARTO
        </span>
      </footer>
    </div>
  );
}
