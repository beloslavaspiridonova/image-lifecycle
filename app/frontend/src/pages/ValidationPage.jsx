import { useEffect, useState } from 'react';
import api from '../lib/api';
import StatusBadge from '../components/StatusBadge';

export default function ValidationPage() {
  const [validations, setValidations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [expanded, setExpanded] = useState(null);

  useEffect(() => {
    api.get('/validations').then(setValidations).catch(() => {}).finally(() => setLoading(false));
  }, []);

  const parseResults = (json) => {
    try { return JSON.parse(json); } catch { return null; }
  };

  return (
    <div>
      <div className="page-header"><h1>Validation</h1></div>
      <div className="card">
        <div className="table-responsive">
          <table className="table table-hover mb-0">
            <thead><tr><th>#</th><th>Build</th><th>Status</th><th>Started</th><th>Finished</th><th>Results</th></tr></thead>
            <tbody>
              {loading && <tr><td colSpan={6} className="text-center py-4"><span className="spinner-border spinner-border-sm" /></td></tr>}
              {!loading && validations.length === 0 && <tr><td colSpan={6} className="text-center text-muted py-3 small">No validations yet</td></tr>}
              {validations.map((v) => {
                const results = parseResults(v.results_json);
                return (
                  <>
                    <tr key={v.id} style={{ cursor: 'pointer' }} onClick={() => setExpanded(expanded === v.id ? null : v.id)}>
                      <td className="text-muted">#{v.id}</td>
                      <td>Build #{v.build_id}</td>
                      <td><StatusBadge status={v.status} /></td>
                      <td className="small text-muted">{v.started_at ? new Date(v.started_at).toLocaleString() : '-'}</td>
                      <td className="small text-muted">{v.finished_at ? new Date(v.finished_at).toLocaleString() : '-'}</td>
                      <td><i className={`bi bi-chevron-${expanded === v.id ? 'up' : 'down'} text-muted`} /></td>
                    </tr>
                    {expanded === v.id && results && (
                      <tr key={`${v.id}-detail`}><td colSpan={6} className="p-0">
                        <div className="p-3 small" style={{ background: 'var(--bg-card)' }}>
                          {results.tests && results.tests.length > 0 ? (
                            <ul className="list-unstyled mb-0">
                              {results.tests.map((t, i) => (
                                <li key={i}><i className={`bi bi-${t.passed ? 'check-circle-fill text-success' : 'x-circle-fill text-danger'} me-2`} />{t.test_name || t.name}</li>
                              ))}
                            </ul>
                          ) : <code className="small">{results.summary}</code>}
                        </div>
                      </td></tr>
                    )}
                  </>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
