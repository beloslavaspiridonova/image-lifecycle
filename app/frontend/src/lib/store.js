import { create } from 'zustand';
import api from './api';

const ROLE_LEVELS = {
  owner: 5,
  service_admin: 4,
  reviewer: 3,
  maintainer: 2,
  viewer: 1,
};

export const useStore = create((set, get) => ({
  user: null,
  roles: [],
  capabilities: [],
  isAuthenticated: false,
  scopeLoaded: false,

  initAuth: async () => {
    try {
      const data = await api.get('/auth/me');
      if (!data) return; // 401 handled by api.js redirect
      set({
        user: data.user,
        roles: data.roles || [],
        capabilities: data.capabilities || [],
        isAuthenticated: true,
        scopeLoaded: true,
      });
    } catch (e) {
      // Not authenticated - leave isAuthenticated false
      set({ scopeLoaded: true });
      console.debug('initAuth failed:', e.message || e);
    }
  },

  logout: async () => {
    try {
      await api.post('/auth/logout');
    } catch (_) {}
    set({
      user: null,
      roles: [],
      capabilities: [],
      isAuthenticated: false,
      scopeLoaded: false,
    });
    window.location.href = '/app/login';
  },

  hasRole: (minRole) => {
    const { roles } = get();
    const minLevel = ROLE_LEVELS[minRole] || 0;
    const userLevel = Math.max(...roles.map((r) => ROLE_LEVELS[r] || 0), 0);
    return userLevel >= minLevel;
  },
}));

export default useStore;
