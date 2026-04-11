// Intentamos obtener la URL de la variable de entorno, si no, usamos la de producción por defecto
const API_BASE = "https://festisafe-production.up.railway.app";
const API_URL = `${API_BASE}/api/v1`;

export async function fetchWithAuth(endpoint: string, options: RequestInit = {}) {
  const token = typeof window !== 'undefined' ? localStorage.getItem('festisafe_token') : null;

  const headers = {
    "Content-Type": "application/json",
    ...(token ? { "Authorization": `Bearer ${token}` } : {}),
    ...options.headers,
  };

  const response = await fetch(`${API_URL}${endpoint}`, {
    ...options,
    headers,
  });

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    throw new Error(errorData.detail || "Error en la petición a la API");
  }

  return response.json();
}

// Funciones de Autenticación
export const authApi = {
  login: async (email: string, pass: string) => {
    const response = await fetch("https://festisafe-production.up.railway.app/api/v1/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password: pass }),
    });
    if (!response.ok) throw new Error("Credenciales inválidas");
    return response.json();
  }
};

// Funciones para el Super Admin
export const adminApi = {
  getCompanies: () => fetchWithAuth("/companies/"),
  createCompany: (data: any) => fetchWithAuth("/companies/", {
    method: "POST",
    body: JSON.stringify(data),
  }),
  getStats: () => fetchWithAuth("/admin/stats"), // Asumiendo que existe un endpoint de métricas
};
