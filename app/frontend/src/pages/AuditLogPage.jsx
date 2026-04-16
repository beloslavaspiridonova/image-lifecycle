import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import api from '../lib/api';
import useStore from '../lib/store';

export default function AuditLogPage() {
  const [entries, setEntries] = useState([]);
  const [loading, setLoading] = useState(true);
  const [actionFilter, setActionFilter] = useState('');
  const [entityFilter, setEntityFilter] = useState('');
  const hasRole = useStore((s) => s.hasRole);
  const navigate = useNavigate();

  useEffect(() => {
    if (!hasRole('service_admin')) { navigate('/'); return; }
    const params = new URLSearchParams({ limit: 100 });
    if (actionFilter) params.set('action', actionFilter);
    if (entityFilter) params.set('entity_type', entityFilter);
    api.get(`/audit?${params}`).then(setEntries).catch(() => {}).finally(() => setLoading(false));
  }, [actionFilter, entityFilter, hasRole, navigate]);

  return (
    <div>
      <div className="page-header"><h1>Audit Log</h1></div>
      <div className="card mb-3">
        <div className="card-body py-2">
          <div className="row g-2">
            <div className="col-sm-4"><input className="form-control form-control-sm" placeholder="Filter by action..." value={actionFilter} onChange={(e) => setActionFilter(e.target.value)} /></div>
            <div className="col-sm-4"><input className="form-control form-control-sm" placeholder="Filter by entity type..." value={entityFilter} onChange={(e) => setEntityFilter(e.target.value)} /></div>
          </div>
        </div>
      </div>
      <div className="card">
        <div className="table-responsive">
          <table className="table table-hover mb-0">
            <thead><tr><th>Time</th><th>User</th><th>Action</th><th>Entity</th><th>Detail</th></tr></thead>
            <tbody>
              {loading && <tr><td colSpan={5} className="text-center py-4"><span className="spinner-border spinner-border-sm" /></td></tr>}
              {!loading && entries.length === 0 && <tr><td colSpan={5} className="text-center text-muted py-3 small">No entries</td></tr>}
              {entries.map && entries.map((e) => (
                <tr key={e.id}>
                  <td className="small text-muted">{e.created_at ? new Date(e.created_at).toLocaleString() : '-'}</td>
                  <td className="small">{e.user_id ? `User #${e.user_id}` : 'system'}</td>
                  <td><code className="small">{e.action}</code></td>
                  <td className="small text-muted">{e.entity_type} {e.entity_id ? `#${e.entity_id}` : ''}</td>
                  <td className="small text-muted" style={{ maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{e.detail}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
