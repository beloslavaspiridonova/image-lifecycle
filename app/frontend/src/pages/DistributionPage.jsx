import { useEffect, useState } from 'react';
import api from '../lib/api';
import useStore from '../lib/store';
import StatusBadge from '../components/StatusBadge';

const REGIONS = [
  { code: 'ZRH', name: 'Zurich', flag: 'CH' },
  { code: 'FRA', name: 'Frankfurt', flag: 'DE' },
  { code: 'SJC', name: 'San Jose', flag: 'US' },
  { code: 'MNL', name: 'Manila', flag: 'PH' },
  { code: 'TYO', name: 'Tokyo', flag: 'JP' },
];

export default function DistributionPage() {
  const [records, setRecords] = useState([]);
  const [publishes, setPublishes] = useState([]);
  const hasRole = useStore((s) => s.hasRole);

  useEffect(() => {
    api.get('/distribution').then(setRecords).catch(() => {});
    api.get('/publish-requests').then(setPublishes).catch(() => {});
  }, []);

  const getRegionStatus = (code) => {
    const regionRecords = records.filter((r) => r.region === code);
    if (regionRecords.length === 0) return null;
    return regionRecords[regionRecords.length - 1];
  };

  const readyPublishes = publishes.filter((p) => p.status === 'published');

  const handleDistribute = async (publishId) => {
    try {
      await api.post(`/distribution/${publishId}/start`);
      api.get('/distribution').then(setRecords).catch(() => {});
      alert('Distribution started');
    } catch (e) {
      alert(e.message);
    }
  };

  return (
    <div>
      <div className="page-header"><h1>Distribution</h1></div>

      <div className="row g-3 mb-4">
        {REGIONS.map((r) => {
          const last = getRegionStatus(r.code);
          return (
            <div key={r.code} className="col-sm-6 col-lg">
              <div className="region-card">
                <div className="region-name">{r.code}</div>
                <div className="text-muted small mb-2">{r.name}</div>
                {last ? <StatusBadge status={last.status} /> : <span className="text-muted small">No data</span>}
              </div>
            </div>
          );
        })}
      </div>

      {hasRole('service_admin') && readyPublishes.length > 0 && (
        <div className="card">
          <div className="card-header small fw-semibold">Distribute a Published Release</div>
          <div className="card-body">
            {readyPublishes.map((p) => (
              <div key={p.id} className="d-flex justify-content-between align-items-center py-1">
                <span className="small">Publish Request #{p.id} - Build #{p.build_id}</span>
                <button className="btn btn-sm text-white" style={{ background: 'var(--cs-green)' }} onClick={() => handleDistribute(p.id)}>
                  <i className="bi bi-diagram-3 me-1" />Distribute
                </button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
