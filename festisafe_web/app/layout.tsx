import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "FestiSafe | Cloud Intelligence Center",
  description: "Sistema de Monitoreo en la Nube y Gestión de Seguridad para Eventos Masivos",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="es" className="dark">
      <body className="bg-[#030712] overflow-x-hidden">
        {/* Capa de Fondo Estático (Radar Grid) */}
        <div className="fixed inset-0 z-0 opacity-10 pointer-events-none"
             style={{ backgroundImage: 'radial-gradient(#ffffff 0.5px, transparent 0.5px)', backgroundSize: '40px 40px' }} />

        {/* Auroras de Fondo Animadas */}
        <div className="fixed top-[-15%] left-[-15%] w-[50%] h-[50%] bg-indigo-600/10 rounded-full blur-[140px] animate-glow pointer-events-none z-0" />
        <div className="fixed bottom-[-15%] right-[-15%] w-[50%] h-[50%] bg-purple-600/5 rounded-full blur-[140px] animate-glow pointer-events-none z-0" style={{ animationDelay: '2s' }} />

        {/* Contenido Principal */}
        <main className="relative z-10 min-h-screen">
          {children}
        </main>
      </body>
    </html>
  );
}
