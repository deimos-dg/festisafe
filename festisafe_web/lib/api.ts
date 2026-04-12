const API_BASE = process.env.NEXT_PUBLIC_API_URL || "https://festisafe-production.up.railway.app";
const API_URL = `${API_BASE}/api/v1`;

const TOKEN_KEY = 'festisafe_token';

export function saveToken(token: string): void {
  if (typeof window === 'undefined') return;
  sessionStorage.setItem(TOKEN_KEY, token);
  // Cookie para que el middleware de Next.js pueda verificar auth en SSR
  document.cookie = 'fs_authed=1; path=/; SameSite=Strict; Max-Age=86400';
}

export function getToken(): string | null {
  if (typeof window === 'undefined') return null;
  return sessionStorage.getItem(TOKEN_KEY);
}

export function clearToken(): void {
  if (typeof window === 'undefined') return;
  sessionStorage.removeItem(TOKEN_KEY);
  document.cookie = 'fs_authed=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT';
}

export async function fetchWithAuth(endpoint: string, options: RequestInit = {}) {
  const token = getToken();

  const headers = {
    "Content-Type": "application/json",
    ...(token ? { "Authorization": `Bearer ${token}` } : {}),
    ...options.headers,
  };

  const response = await fetch(`${API_URL}${endpoint}`, { ...options, headers });

  if (response.status === 401) {
    clearToken();
    if (typeof window !== 'undefined') window.location.href = '/';
    throw new Error('Sesión expirada');
  }

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    throw new Error(errorData.detail || "Error en la petición a la API");
  }

  return response.json();
}

export const authApi = {
  login: async (email: string, pass: string) => {
    const response = await fetch(`${API_URL}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password: pass }),
    });
    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(errorData.detail || "Credenciales inválidas");
    }
    return response.json();
  }
};

export const adminApi = {
  getCompanies: () => fetchWithAuth("/companies/"),
  createCompany: (data: unknown) => fetchWithAuth("/companies/", {
    method: "POST",
    body: JSON.stringify(data),
  }),
  getStats: () => fetchWithAuth("/admin/stats"),
  getEmployees: () => fetchWithAuth("/users/active"),
  getRecentAlerts: () => fetchWithAuth("/sos/recent"),
};
