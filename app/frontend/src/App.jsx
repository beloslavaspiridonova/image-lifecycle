import { useEffect, useState } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import useStore from './lib/store';
import Sidebar from './components/Sidebar';

import LoginPage from './pages/LoginPage';
import DashboardPage from './pages/DashboardPage';
import CandidatesPage from './pages/CandidatesPage';
import BuildRunsPage from './pages/BuildRunsPage';
import ValidationPage from './pages/ValidationPage';
import PublishQueuePage from './pages/PublishQueuePage';
import DistributionPage from './pages/DistributionPage';
import AuditLogPage from './pages/AuditLogPage';
import SettingsPage from './pages/SettingsPage';

function AppShell({ children }) {
  return (
    <div className="d-flex vh-100">
      <Sidebar />
      <div className="flex-grow-1 d-flex flex-column overflow-hidden">
        <div className="top-accent-bar"></div>
        <main
          className="flex-grow-1 p-4"
          style={{ background: 'var(--bg-body)', overflowY: 'auto', position: 'relative' }}
        >
          {children}
        </main>
      </div>
    </div>
  );
}

export default function App() {
  const isAuthenticated = useStore((s) => s.isAuthenticated);
  const scopeLoaded = useStore((s) => s.scopeLoaded);
  const initAuth = useStore((s) => s.initAuth);
  const [authReady, setAuthReady] = useState(false);

  useEffect(() => {
    let cancelled = false;
    const run = async () => {
      try {
        await initAuth();
      } catch (e) {
        console.error('initAuth error:', e);
      } finally {
        if (!cancelled) setAuthReady(true);
      }
    };
    run();
    // Safety timeout
    const timer = setTimeout(() => { if (!cancelled) setAuthReady(true); }, 8000);
    return () => { cancelled = true; clearTimeout(timer); };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  if (!authReady) {
    return (
      <div className="d-flex justify-content-center align-items-center vh-100">
        <div className="spinner-border" style={{ color: 'var(--cs-green)' }} role="status"></div>
      </div>
    );
  }

  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      {isAuthenticated ? (
        <Route
          path="/*"
          element={
            <AppShell>
              <Routes>
                <Route path="/" element={<DashboardPage />} />
                <Route path="/candidates" element={<CandidatesPage />} />
                <Route path="/builds" element={<BuildRunsPage />} />
                <Route path="/validation" element={<ValidationPage />} />
                <Route path="/publish" element={<PublishQueuePage />} />
                <Route path="/distribution" element={<DistributionPage />} />
                <Route path="/audit" element={<AuditLogPage />} />
                <Route path="/settings" element={<SettingsPage />} />
                <Route path="*" element={<Navigate to="/" replace />} />
              </Routes>
            </AppShell>
          }
        />
      ) : (
        <Route path="*" element={<Navigate to="/login" replace />} />
      )}
    </Routes>
  );
}
