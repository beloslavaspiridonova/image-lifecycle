/**
 * API client for Image Lifecycle backend.
 * Uses httponly session cookie (credentials: 'include').
 * 401 responses redirect to /login.
 */

async function request(method, path, body = null) {
  const headers = { 'Content-Type': 'application/json' };
  const opts = { method, headers, credentials: 'include' };
  if (body !== null) opts.body = JSON.stringify(body);

  const res = await fetch(`/api${path}`, opts);

  if (res.status === 401) {
    window.location.href = '/app/login';
    return null;
  }

  const data = await res.json().catch(() => null);

  if (!res.ok) {
    const err = new Error(data?.detail || data?.message || `HTTP ${res.status}`);
    err.status = res.status;
    throw err;
  }

  return data;
}

export const api = {
  get: (path) => request('GET', path),
  post: (path, body) => request('POST', path, body),
  put: (path, body) => request('PUT', path, body ?? null),
  patch: (path, body) => request('PATCH', path, body),
  del: (path) => request('DELETE', path),
};

export default api;
