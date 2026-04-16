import { useEffect, useState } from 'react';
import api from '../lib/api';
import useStore from '../lib/store';
import StatusBadge from '../components/StatusBadge';

export default function PublishQueuePage() {
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const hasRole = useStore((s) => s.hasRole);

  const load = () => api.get('/publish-requests').then(setRequests).catch(() => {}).finally(() => setLoading(false));
  useEffect(() => { load(); }, []);

  const act = async (id, action) => {
    try {
      await api.put(`/publish-requests/${id}/${action}`);
      load();
    } catch (e) {
      alert(e.message);
    }
  };

  const pending = requests.filter((r) => r.status === 'pending');
  const resolved = requests.filter((r) => r.status !== 'pending');

  return (
    <div>
      <div className="page-header"><h1>Publish Queue</h1></div>

      <h6 className="text-muted small text-uppercase mb-2">Pending</h6>
      <div className="card mb-4">
        <div className="table-responsive">
          <table className="table table-hover mb-0">
            <thead><tr><th>#</th><th>Build</th><th>Status</th><th>Created</th><th>Notes</th><th>Actions</th></tr></thead>
            <tbody>
              {loading && <tr><td colSpan={6} className="text-center py-3"><span className="spinner-border spinner-border-sm" /></td></tr>}
              {!loading && pending.length === 0 && <tr><td colSpan={6} className="text-center text-muted py-3 small">No pending requests</td></tr>}
              {pending.map((r) => (
                <tr key={r.id}>
                  <td className="text-muted">#{r.id}</td>
                  <td>Build #{r.build_id}</td>
                  <td><StatusBadge status={r.status} /></td>
                  <td className="small text-muted">{r.created_at ? new Date(r.created_at).toLocaleDateString() : '-'}</td>
                  <td className="small text-muted">{r.notes || '-'}</td>
                  <td className="d-flex gap-1">
                    {hasRole('reviewer') && <>
                      <button className="btn btn-sm btn-success" onClick={() => act(r.id, 'approve')}>Approve</button>
                      <button className="btn btn-sm btn-danger" onClick={() => act(r.id, 'reject')}>Reject</button>
                    </>}
                    {hasRole('owner') && <button className="btn btn-sm btn-outline-primary" onClick={() => act(r.id, 'confirm-mi')}>Confirm MI</button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <h6 className="text-muted small text-uppercase mb-2">Resolved</h6>
      <div className="card">
        <div className="table-responsive">
          <table className="table mb-0">
            <thead><tr><th>#</th><th>Build</th><th>Status</th><th>Notes</th></tr></thead>
            <tbody>
              {resolved.length === 0 && <tr><td colSpan={4} className="text-center text-muted py-3 small">None yet</td></tr>}
              {resolved.map((r) => (
                <tr key={r.id}>
                  <td className="text-muted">#{r.id}</td>
                  <td>Build #{r.build_id}</td>
                  <td><StatusBadge status={r.status} /></td>
                  <td className="small text-muted">{r.notes || '-'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
