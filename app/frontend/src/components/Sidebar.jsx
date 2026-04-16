import { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import useStore from '../lib/store';

const NAV_ITEMS = [
  { icon: 'bi-speedometer2', label: 'Dashboard', path: '/' },
  { icon: 'bi-cloud-upload', label: 'Candidates', path: '/candidates' },
  { icon: 'bi-hammer', label: 'Build Runs', path: '/builds' },
  { icon: 'bi-check2-circle', label: 'Validation', path: '/validation' },
  { icon: 'bi-send-check', label: 'Publish Queue', path: '/publish' },
  { icon: 'bi-globe2', label: 'Distribution', path: '/distribution' },
];

const ADMIN_NAV_ITEMS = [
  { icon: 'bi-shield-lock', label: 'Audit Log', path: '/audit', minRole: 'service_admin' },
  { icon: 'bi-gear', label: 'Settings', path: '/settings', minRole: 'service_admin' },
];

const Theme = {
  get() { return localStorage.getItem('ilm-theme') || 'system'; },
  set(pref) {
    localStorage.setItem('ilm-theme', pref);
    this.apply(pref);
  },
  apply(pref) {
    let theme;
    if (pref === 'system') {
      theme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    } else {
      theme = pref;
    }
    document.documentElement.setAttribute('data-bs-theme', theme);
  },
  cycle() {
    const order = ['system', 'light', 'dark'];
    const cur = this.get();
    const next = order[(order.indexOf(cur) + 1) % order.length];
    this.set(next);
    return next;
  },
};

export default function Sidebar() {
  const user = useStore((s) => s.user);
  const logout = useStore((s) => s.logout);
  const hasRole = useStore((s) => s.hasRole);
  const navigate = useNavigate();
  const location = useLocation();
  const [theme, setTheme] = useState(Theme.get());

  useEffect(() => {
    Theme.apply(Theme.get());
  }, []);

  const themeIcon = theme === 'dark' ? 'bi-sun' : theme === 'light' ? 'bi-moon' : 'bi-circle-half';
  const themeLabel = theme === 'dark' ? 'Dark' : theme === 'light' ? 'Light' : 'System';

  const isActive = (path) => {
    if (path === '/') return location.pathname === '/';
    return location.pathname.startsWith(path);
  };

  return (
    <div className="sidebar">
      {/* Brand */}
      <div className="sidebar-brand">
        <i className="bi bi-layers-half" style={{ fontSize: '1.1rem' }}></i>
        <div>
          Image Lifecycle
          <span className="brand-sub">CloudSigma</span>
        </div>
      </div>

      {/* Nav */}
      <nav className="sidebar-nav">
        {NAV_ITEMS.map((item) => (
          <a
            key={item.path}
            href="#"
            className={`nav-link ${isActive(item.path) ? 'active' : ''}`}
            onClick={(e) => { e.preventDefault(); navigate(item.path); }}
          >
            <i className={`bi ${item.icon}`}></i>
            {item.label}
          </a>
        ))}

        {/* Admin section - show only for service_admin+ */}
        {hasRole('service_admin') && (
          <>
            <div className="sidebar-section-label mt-2">Admin</div>
            {ADMIN_NAV_ITEMS.map((item) => (
              <a
                key={item.path}
                href="#"
                className={`nav-link ${isActive(item.path) ? 'active' : ''}`}
                onClick={(e) => { e.preventDefault(); navigate(item.path); }}
              >
                <i className={`bi ${item.icon}`}></i>
                {item.label}
              </a>
            ))}
          </>
        )}
      </nav>

      {/* Footer */}
      <div className="sidebar-footer">
        <div className="sidebar-user">
          <strong>{user?.name || user?.email || 'User'}</strong>
          {user?.email && user?.name && (
            <span style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>{user.email}</span>
          )}
        </div>
        <button
          className="btn btn-sm btn-outline-danger w-100 mb-1"
          style={{ fontSize: '0.78rem' }}
          onClick={logout}
        >
          <i className="bi bi-box-arrow-right me-1"></i>Logout
        </button>
        <button
          className="theme-toggle"
          onClick={() => { const next = Theme.cycle(); setTheme(next); }}
        >
          <i className={`bi ${themeIcon}`}></i>
          {themeLabel}
        </button>
      </div>
    </div>
  );
}
