import { useEffect, useState } from 'react';
import api from '../lib/api';
import useStore from '../lib/store';

function StatCard({ icon, label, value, color }) {
  return (
    <div className="card stat-card">
      <div className="d-flex justify-content-between align-items-start">
        <div>
          <div className="stat-value">{value ?? '-'}</div>
          <div className="stat-label">{label}</div>
        </div>
        <i className={`bi ${icon} stat-icon`} style={{ color: color || 'var(--cs-green)' }} />
      </div>
    </div>
  );
}

export default function DashboardPage() {
  const [builds, setBuilds] = useState([]);
  const [publishes, setPublishes] = useState([]);
  const [audit, setAudit] = useState([]);
  const [health, setHealth] = useState(null);
  const hasRole = useStore((s) => s.hasRole);

  useEffect(() => {
    api.get('/builds').then(setBuilds).catch(() => {});
    api.get('/publish-requests').then(setPublishes).catch(() => {});
    api.get('/audit?limit=10').then(setAudit).catch(() => {});
    api.get('/system/health').then(setHealth).catch(() => {});
  }, []);

  const activeBuilds = builds.filter((b) => b.status === 'running').length;
  const pendingApprovals = publishes.filter((p) => p.status === 'pending').length;

  const handleDiscover = async () => {
    try {
      await api.post('/candidates/discover');
      alert('Discovery started');
    } catch (e) {
      alert(e.message);
    }
  };

  return (
    <div>
      <div className="page-header d-flex justify-content-between align-items-center">
        <h1>Dashboard</h1>
        {hasRole('service_admin') && (
          <button className="btn btn-sm text-white" style={{ background: 'var(--cs-green)' }} onClick={handleDiscover}>
            <i className="bi bi-search me-1" />Run Discovery
          </button>
        )}
      </div>

      <div className="row g-3 mb-4">
        <div className="col-sm-6 col-lg-3"><StatCard icon="bi-hammer" label="Active Builds" value={activeBuilds} /></div>
        <div className="col-sm-6 col-lg-3"><StatCard icon="bi-hourglass-split" label="Pending Approvals" value={pendingApprovals} color="#E0A55A" /></div>
        <div className="col-sm-6 col-lg-3"><StatCard icon="bi-globe2" label="Regions" value={5} /></div>
        <div className="col-sm-6 col-lg-3"><StatCard icon="bi-heart-pulse" label="System" value={health?.status === 'ok' ? 'Healthy' : 'Unknown'} color={health?.status === 'ok' ? 'var(--cs-green)' : '#dc3545'} /></div>
      </div>

      <div className="card">
        <div className="card-header small fw-semibold">Recent Activity</div>
        <div className="table-responsive">
          <table className="table table-hover mb-0">
            <thead><tr><th>Time</th><th>Action</th><th>Entity</th><th>Detail</th></tr></thead>
            <tbody>
              {audit.length === 0 && <tr><td colSpan={4} className="text-center text-muted py-3 small">No activity yet</td></tr>}
              {audit.map && audit.map ? audit.map((e) => (
                <tr key={e.id}>
                  <td className="text-muted small">{e.created_at ? new Date(e.created_at).toLocaleString() : '-'}</td>
                  <td><code className="small">{e.action}</code></td>
                  <td className="small">{e.entity_type} {e.entity_id ? `#${e.entity_id}` : ''}</td>
                  <td className="small text-muted">{e.detail}</td>
                </tr>
              )) : null}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
