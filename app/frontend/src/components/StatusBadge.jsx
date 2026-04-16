export default function StatusBadge({ status }) {
  const map = {
    pending: 'warning',
    running: 'info',
    in_progress: 'info',
    passed: 'success',
    approved: 'success',
    published: 'success',
    complete: 'success',
    failed: 'danger',
    rejected: 'danger',
    staged: 'secondary',
  };
  const color = map[status] || 'secondary';
  const spinning = status === 'running' || status === 'in_progress';
  return (
    <span className={`badge bg-${color}`}>
      {spinning && (
        <span className="spinner-border spinner-border-sm me-1" role="status" />
      )}
      {status}
    </span>
  );
}
