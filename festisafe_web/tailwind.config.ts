import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        festisafe: {
          primary: "#0D1B4B",     // Azul marino (Base de la App)
          secondary: "#1A3A6B",   // Azul intermedio
          accent: "#2962FF",      // Azul vibrante (botones)
          background: "#121212",  // Fondo oscuro estándar
        },
      },
    },
  },
  plugins: [],
};
export default config;
