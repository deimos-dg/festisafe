import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: 'standalone',
  // Permite que el servidor standalone escuche en cualquier hostname (necesario en Railway)
  experimental: {
    serverActions: {
      allowedOrigins: ['*'],
    },
  },
};

export default nextConfig;
