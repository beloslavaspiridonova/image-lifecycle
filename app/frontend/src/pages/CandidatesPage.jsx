import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import api from '../lib/api';
import useStore from '../lib/store';
import StatusBadge from '../components/StatusBadge';

export default function CandidatesPage() {
  const [candidates, setCandidates] = useState([]);
  const [loading, setLoading] = useState(true);
  const hasRole = useStore((s) => s.hasRole);
  const navigate = useNavigate();

  const load = () => api.get('/candidates').then(setCandidates).catch(() => {}).finally(() => setLoading(false));
  useEffect(() => { load(); }, []);

  const handleDiscover = async () => {
    try {
      await api.post('/candidates/discover');
      alert('Discovery started - refresh in a moment');
    } catch (e) {
      alert(e.message);
    }
  };

  const handlePromoteBuild = async (candidateId) => {
    try {
      await api.post('/builds', { candidate_id: candidateId });
      navigate('/builds');
    } catch (e) {
      alert(e.message);
    }
  };

  return (
    <div>
      <div className="page-header d-flex justify-content-between align-items-center">
        <h1>Candidates</h1>
        {hasRole('service_admin') && (
          <button className="btn btn-sm text-white" style={{ background: 'var(--cs-green)' }} onClick={handleDiscover}>
            <i className="bi bi-search me-1" />Run Discovery
          </button>
        )}
      </div>
      <div className="card">
        <div className="table-responsive">
          <table className="table table-hover mb-0">
            <thead><tr><th>Vendor</th><th>OS</th><th>Version</th><th>Status</th><th>Discovered</th><th>Actions</th></tr></thead>
            <tbody>
              {loading && <tr><td colSpan={6} className="text-center py-4"><span className="spinner-border spinner-border-sm" /></td></tr>}
              {!loading && candidates.length === 0 && <tr><td colSpan={6} className="text-center text-muted py-3 small">No candidates yet - run discovery</td></tr>}
              {candidates.map((c) => (
                <tr key={c.id}>
                  <td>{c.vendor}</td><td>{c.os_name}</td><td>{c.version}</td>
                  <td><StatusBadge status={c.status} /></td>
                  <td className="text-muted small">{c.discovered_at ? new Date(c.discovered_at).toLocaleDateString() : '-'}</td>
                  <td>
                    {hasRole('maintainer') && (
                      <button className="btn btn-sm btn-outline-primary" onClick={() => handlePromoteBuild(c.id)}>
                        <i className="bi bi-hammer me-1" />Build
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
