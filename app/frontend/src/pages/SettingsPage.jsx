import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import api from '../lib/api';
import useStore from '../lib/store';

export default function SettingsPage() {
  const [tab, setTab] = useState('system');
  const [status, setStatus] = useState(null);
  const [users, setUsers] = useState([]);
  const hasRole = useStore((s) => s.hasRole);
  const navigate = useNavigate();

  useEffect(() => {
    if (!hasRole('service_admin')) { navigate('/'); return; }
    api.get('/system/status').then(setStatus).catch(() => {});
    api.get('/settings/users').then(setUsers).catch(() => {});
  }, [hasRole, navigate]);

  return (
    <div>
      <div className="page-header"><h1>Settings</h1></div>
      <ul className="nav nav-tabs mb-3">
        <li className="nav-item"><button className={`nav-link ${tab === 'system' ? 'active' : ''}`} onClick={() => setTab('system')}>System</button></li>
        <li className="nav-item"><button className={`nav-link ${tab === 'users' ? 'active' : ''}`} onClick={() => setTab('users')}>Users</button></li>
      </ul>

      {tab === 'system' && status && (
        <div className="card">
          <div className="card-body">
            <table className="table table-sm mb-0">
              <tbody>
                <tr><td className="text-muted small fw-semibold">Scripts Dir</td><td className="small"><code>{status.scripts_dir}</code></td></tr>
                <tr><td className="text-muted small fw-semibold">API Base</td><td className="small"><code>{status.cs_api_base}</code></td></tr>
                <tr><td className="text-muted small fw-semibold">Version</td><td className="small">{status.version}</td></tr>
                {status.db_stats && Object.entries(status.db_stats).map(([k, v]) => (
                  <tr key={k}><td className="text-muted small fw-semibold">{k}</td><td className="small">{v} rows</td></tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {tab === 'users' && (
        <div className="card">
          <div className="table-responsive">
            <table className="table table-hover mb-0">
              <thead><tr><th>Email</th><th>Name</th><th>Roles</th><th>Active</th></tr></thead>
              <tbody>
                {users.length === 0 && <tr><td colSpan={4} className="text-center text-muted py-3 small">No users</td></tr>}
                {users.map && users.map((u) => (
                  <tr key={u.id}>
                    <td className="small">{u.email}</td>
                    <td className="small">{u.name || '-'}</td>
                    <td>{(u.roles || []).map((r) => <span key={r} className="badge bg-secondary me-1 small">{r}</span>)}</td>
                    <td>{u.is_active ? <span className="badge bg-success">active</span> : <span className="badge bg-danger">inactive</span>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
