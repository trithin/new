const API_BASE = '/api';

export function saveToken(token) {
  localStorage.setItem('token', token);
}

export function getToken() {
  return localStorage.getItem('token');
}

export function clearToken() {
  localStorage.removeItem('token');
}

export async function api(path, options = {}) {
  const token = getToken();
  const headers = {
    'Content-Type': 'application/json',
    ...(options.headers || {}),
  };

  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers,
  });

  if (res.status === 401 || res.status === 403) {
    const normalizedPath = location.pathname.replace(/\/+$/, '');
    const isLoginPage = normalizedPath === '' || normalizedPath === '/index.html';
    if (!path.startsWith('/auth/login')) {
      clearToken();
      if (!isLoginPage) {
        location.href = '/index.html';
      }
    }
  }

  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : {};
  } catch (_) {
    data = { raw: text };
  }

  if (!res.ok) {
    throw new Error(data.message || `Request failed: ${res.status}`);
  }

  return data;
}

export function ensureAuth() {
  if (!getToken()) {
    location.href = '/index.html';
  }
}

export function formatMoney(value) {
  return `${Number(value || 0).toLocaleString('vi-VN')} VNĐ`;
}
