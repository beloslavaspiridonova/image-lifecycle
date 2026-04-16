import { useEffect, useState } from 'react';
import api from '../lib/api';
import useStore from '../lib/store';
import StatusBadge from '../components/StatusBadge';

export default function BuildRunsPage() {
  const [builds, setBuilds] = useState([]);
  const [loading, setLoading] = useState(true);
  const [logsModal, setLogsModal] = useState(null);
  const [logsContent, setLogsContent] = useState('');
  const hasRole = useStore((s) => s.hasRole);

  const load = () => api.get('/builds').then(setBuilds).catch(() => {}).finally(() => setLoading(false));
  useEffect(() => { load(); }, []);

  const showLogs = async (build) => {
    setLogsModal(build);
    try {
      const res = await fetch(`/api/builds/${build.id}/logs`, { credentials: 'include' });
      setLogsContent(await res.text());
    } catch {
      setLogsContent('Failed to load logs');
    }
  };

  const startValidation = async (buildId) => {
    try {
      await api.post(`/validations/${buildId}/start`);
      alert('Validation started');
    } catch (e) {
      alert(e.message);
    }
  };

  return (
    <div>
      <div className="page-header"><h1>Build Runs</h1></div>
      <div className="card">
        <div className="table-responsive">
          <table className="table table-hover mb-0">
            <thead><tr><th>#</th><th>Image</th><th>Status</th><th>Started</th><th>Finished</th><th>Actions</th></tr></thead>
            <tbody>
              {loading && <tr><td colSpan={6} className="text-center py-4"><span className="spinner-border spinner-border-sm" /></td></tr>}
              {!loading && builds.length === 0 && <tr><td colSpan={6} className="text-center text-muted py-3 small">No builds yet</td></tr>}
              {builds.map((b) => (
                <tr key={b.id}>
                  <td className="text-muted">#{b.id}</td>
                  <td>{b.image_name || <span className="text-muted small">pending</span>}</td>
                  <td><StatusBadge status={b.status} /></td>
                  <td className="small text-muted">{b.started_at ? new Date(b.started_at).toLocaleString() : '-'}</td>
                  <td className="small text-muted">{b.finished_at ? new Date(b.finished_at).toLocaleString() : '-'}</td>
                  <td className="d-flex gap-1">
                    <button className="btn btn-sm btn-outline-secondary" onClick={() => showLogs(b)}><i className="bi bi-file-text" /></button>
                    {hasRole('maintainer') && b.status === 'passed' && (
                      <button className="btn btn-sm btn-outline-primary" onClick={() => startValidation(b.id)}><i className="bi bi-check2-circle" /></button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {logsModal && (
        <div className="modal d-block" style={{ background: 'rgba(0,0,0,0.5)' }} onClick={() => setLogsModal(null)}>
          <div className="modal-dialog modal-lg" onClick={(e) => e.stopPropagation()}>
            <div className="modal-content">
              <div className="modal-header">
                <h6 className="modal-title">Build #{logsModal.id} Logs</h6>
                <button className="btn-close" onClick={() => setLogsModal(null)} />
              </div>
              <div className="modal-body">
                <pre style={{ maxHeight: 400, overflow: 'auto', fontSize: '0.8rem', background: 'var(--bg-card)', padding: '1rem', borderRadius: 4 }}>{logsContent || 'No logs yet'}</pre>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
