import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import api from '../lib/api';
import useStore from '../lib/store';

export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const initAuth = useStore((s) => s.initAuth);
  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      await api.post('/auth/login', { email, password });
      await initAuth();
      navigate('/');
    } catch (err) {
      setError(err.message || 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="d-flex justify-content-center align-items-center vh-100" style={{ background: 'var(--bg-body)' }}>
      <div style={{ width: '100%', maxWidth: 400 }}>
        <div className="card shadow">
          <div className="card-header text-white py-3 text-center" style={{ background: 'var(--cs-green)' }}>
            <h5 className="mb-0 fw-bold">Image Lifecycle</h5>
            <small style={{ opacity: 0.85 }}>CloudSigma Internal</small>
          </div>
          <div className="card-body p-4">
            {error && <div className="alert alert-danger py-2 small">{error}</div>}
            <form onSubmit={handleSubmit}>
              <div className="mb-3">
                <label className="form-label small fw-semibold">Email</label>
                <input type="email" className="form-control" value={email} onChange={(e) => setEmail(e.target.value)} required autoFocus />
              </div>
              <div className="mb-3">
                <label className="form-label small fw-semibold">Password</label>
                <input type="password" className="form-control" value={password} onChange={(e) => setPassword(e.target.value)} required />
              </div>
              <button type="submit" className="btn w-100 text-white" style={{ background: 'var(--cs-green)' }} disabled={loading}>
                {loading ? <span className="spinner-border spinner-border-sm me-2" /> : null}
                Sign In
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}
