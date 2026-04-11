'use client';

import { useState, useEffect } from 'react';

export default function PortalMapPage() {
  const [employees, setEmployees] = useState<any[]>([]);
  const [activeSOS, setActiveSOS] = useState<any>(null);
  const [showHeatmap, setShowHeatmap] = useState(false);
  const [broadcastTitle, setBroadcastTitle] = useState('');
  const [broadcastContent, setBroadcastContent] = useState('');

  useEffect(() => {
    // Datos simulados con estados reales
    setEmployees([
      { id: '1', name: 'Oficial Juan', role: 'Seguridad', lat: 19.4326, lng: -99.1332, battery: 12, status: 'warning', lastSeen: '2m ago' },
      { id: '2', name: 'Dra. Elena', role: 'Medico', lat: 19.4335, lng: -99.1340, battery: 42, status: 'ok', lastSeen: 'Online' },
      { id: '3', name: 'Staff Carlos', role: 'Logistica', lat: 19.4318, lng: -99.1325, battery: 88, status: 'ok', lastSeen: 'Online' },
    ]);
  }, []);

  return (
    <div className="relative h-screen w-full bg-[#0f172a] overflow-hidden font-sans antialiased text-slate-200">

      {/* Background Map Placeholder (Inmerse Dark Mode) */}
      <div className="absolute inset-0 z-0 bg-slate-900">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,_var(--tw-gradient-stops))] from-indigo-500/10 via-transparent to-transparent opacity-50" />
        <div className="absolute inset-0 grid grid-cols-[repeat(40,minmax(0,1fr))] grid-rows-[repeat(40,minmax(0,1fr))] opacity-10">
          {[...Array(1600)].map((_, i) => (
            <div key={i} className="border-[0.5px] border-slate-700/30" />
          ))}
        </div>
      </div>

      {/* Floating Header */}
      <nav className="absolute top-6 left-6 right-6 z-30 flex justify-between items-center px-6 py-4 bg-slate-900/40 backdrop-blur-xl border border-white/10 rounded-3xl shadow-2xl">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-indigo-600 rounded-2xl flex items-center justify-center shadow-lg shadow-indigo-500/30">
            <span className="text-xl font-black text-white">F</span>
          </div>
          <div>
            <h1 className="text-lg font-bold tracking-tight text-white">FestiSafe <span className="text-indigo-400 font-medium text-sm">Control Center</span></h1>
            <p className="text-[10px] text-slate-400 uppercase tracking-[0.2em]">Live Monitoring System</p>
          </div>
        </div>

        <div className="flex items-center gap-4">
          <div className="px-4 py-2 bg-slate-800/50 rounded-full border border-slate-700/50 flex items-center gap-2">
            <div className="w-2 h-2 bg-emerald-500 rounded-full animate-pulse shadow-[0_0_8px_rgba(16,185,129,0.8)]" />
            <span className="text-xs font-semibold text-slate-300">System Online</span>
          </div>
        </div>
      </nav>

      {/* Sidebar Control - Glassmorphism */}
      <aside className="absolute top-28 left-6 bottom-6 w-80 z-20 flex flex-col gap-6">

        {/* SOS Panel */}
        {activeSOS && (
          <div className="p-6 bg-red-500/20 backdrop-blur-2xl border border-red-500/50 rounded-[2rem] shadow-[0_0_50px_rgba(239,68,68,0.3)] animate-pulse">
            <div className="flex items-center gap-4 mb-2">
              <span className="text-2xl">🚨</span>
              <h2 className="text-xl font-black text-red-100 uppercase italic">SOS Active</h2>
            </div>
            <p className="text-sm text-red-200/80 font-medium">Employee: {activeSOS.name}</p>
          </div>
        )}

        {/* Intelligence Module */}
        <div className="flex-1 bg-slate-900/40 backdrop-blur-xl border border-white/10 rounded-[2.5rem] p-6 shadow-2xl overflow-y-auto overflow-x-hidden">

          <div className="mb-8">
            <h3 className="text-xs font-black text-slate-500 uppercase tracking-widest mb-4">Tactical Tools</h3>
            <div className="grid grid-cols-2 gap-3">
              <button
                onClick={() => setShowHeatmap(!showHeatmap)}
                className={`flex flex-col items-center justify-center p-4 rounded-2xl border transition-all duration-300 gap-2 ${showHeatmap ? 'bg-orange-500/20 border-orange-500 text-orange-200 shadow-lg shadow-orange-500/20' : 'bg-slate-800/40 border-slate-700 text-slate-400 hover:bg-slate-800'}`}
              >
                <span className="text-xl">🔥</span>
                <span className="text-[10px] font-bold">HEATMAP</span>
              </button>
              <button className="flex flex-col items-center justify-center p-4 rounded-2xl border bg-slate-800/40 border-slate-700 text-slate-400 hover:bg-slate-800 transition-all gap-2">
                <span className="text-xl">🌐</span>
                <span className="text-[10px] font-bold">GEOFENCE</span>
              </button>
            </div>
          </div>

          <div className="mb-8">
            <h3 className="text-xs font-black text-slate-500 uppercase tracking-widest mb-4">Device Health</h3>
            <div className="space-y-3">
              {employees.filter(e => e.battery < 20).map(e => (
                <div key={e.id} className="p-4 bg-red-500/10 border border-red-500/20 rounded-2xl flex items-center justify-between group hover:bg-red-500/20 transition-all">
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-lg bg-red-500/20 flex items-center justify-center text-sm font-bold text-red-400">
                      {e.name[0]}
                    </div>
                    <div>
                      <p className="text-xs font-bold text-red-100">{e.name}</p>
                      <p className="text-[10px] text-red-400/60 uppercase font-black tracking-tighter text-left text-wrap max-w-24">Battery Critical</p>
                    </div>
                  </div>
                  <span className="text-xs font-black text-red-500 animate-bounce">🪫 {e.battery}%</span>
                </div>
              ))}
            </div>
          </div>

          <div>
            <h3 className="text-xs font-black text-slate-500 uppercase tracking-widest mb-4">Mass Broadcast</h3>
            <div className="space-y-3">
              <input
                type="text"
                placeholder="Alert Title"
                value={broadcastTitle}
                onChange={(e) => setBroadcastTitle(e.target.value)}
                className="w-full bg-slate-900/50 border border-slate-700/50 rounded-xl px-4 py-3 text-xs outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500/30 transition-all text-white"
              />
              <textarea
                placeholder="Message for all employees..."
                value={broadcastContent}
                onChange={(e) => setBroadcastContent(e.target.value)}
                className="w-full bg-slate-900/50 border border-slate-700/50 rounded-xl px-4 py-3 text-xs outline-none h-24 resize-none focus:border-indigo-500 transition-all text-white"
              />
              <button className="w-full py-4 bg-indigo-600 hover:bg-indigo-500 text-white rounded-2xl font-black text-[10px] tracking-[0.2em] shadow-lg shadow-indigo-600/20 transition-all transform active:scale-95">
                SEND BROADCAST 📢
              </button>
            </div>
          </div>
        </div>
      </aside>

      {/* Interactive Map Area (Visual Pings) */}
      <main className="absolute inset-0 z-10 flex items-center justify-center pointer-events-none">

        {/* Heatmap Layer Effect */}
        {showHeatmap && (
          <div className="absolute inset-0 bg-orange-600/10 backdrop-blur-[2px] pointer-events-none">
             <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-orange-600/20 rounded-full blur-[100px] animate-pulse" />
          </div>
        )}

        {/* Dummy Employee Markers (Pings) */}
        {employees.map(emp => (
          <div key={emp.id} className="absolute pointer-events-auto group cursor-pointer" style={{ top: `${45 + (parseInt(emp.id)*2)}%`, left: `${50 + (parseInt(emp.id)*4)}%` }}>
            <div className="relative">
              <div className={`absolute -inset-4 rounded-full animate-ping opacity-20 ${emp.status === 'warning' ? 'bg-red-500' : 'bg-indigo-500'}`} />
              <div className={`w-4 h-4 rounded-full border-2 border-white shadow-lg ${emp.status === 'warning' ? 'bg-red-500' : 'bg-indigo-500'}`} />

              <div className="absolute top-6 left-1/2 -translate-x-1/2 bg-slate-900 border border-slate-700 px-3 py-2 rounded-xl opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap shadow-2xl">
                <p className="text-[10px] font-black text-white">{emp.name}</p>
                <div className="flex items-center gap-2 mt-1">
                  <span className="text-[8px] text-slate-500 uppercase font-bold">{emp.role}</span>
                  <span className="text-[8px] px-1 bg-slate-800 text-slate-300 rounded uppercase">{emp.lastSeen}</span>
                </div>
              </div>
            </div>
          </div>
        ))}
      </main>

      {/* Global Status Bar (Bottom) */}
      <footer className="absolute bottom-6 left-96 right-6 h-12 z-30 flex items-center justify-between px-6 bg-slate-900/40 backdrop-blur-md border border-white/5 rounded-2xl shadow-xl">
        <div className="flex gap-6 items-center">
          <div className="text-[10px] font-bold text-slate-400 uppercase tracking-widest flex items-center gap-2">
            <span className="w-1.5 h-1.5 bg-indigo-500 rounded-full shadow-[0_0_5px_rgba(99,102,241,0.8)]" />
            Active Staff: <span className="text-white ml-1">{employees.length}</span>
          </div>
          <div className="text-[10px] font-bold text-slate-400 uppercase tracking-widest flex items-center gap-2">
            <span className="w-1.5 h-1.5 bg-red-500 rounded-full shadow-[0_0_5px_rgba(239,68,68,0.8)]" />
            Risk Alerts: <span className="text-white ml-1">{employees.filter(e => e.status === 'warning').length}</span>
          </div>
        </div>
        <div className="text-[9px] font-black text-slate-500 tracking-[0.3em] italic uppercase">
          Signal Strength: <span className="text-indigo-400">Stable</span>
        </div>
      </footer>
    </div>
  );
}
