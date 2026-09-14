import { useCallback, useEffect, useMemo, useState } from 'react';
import { Navigate } from 'react-router-dom';
import { AlertTriangle, CheckCircle2, Cloud, CloudOff, History, RefreshCw, WifiOff } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import {
  getOfflineMutations,
  getOfflineSyncHistory,
  syncOfflineMutations,
  subscribeToOfflineSync,
  type OfflineMutation,
  type OfflineSyncHistory,
} from '@/lib/offlineSync';

function endpointLabel(url: string): string {
  try {
    const parsed = new URL(url);
    const match = parsed.pathname.match(/\/rest\/v1\/([^/]+)/);
    return match?.[1] ?? parsed.pathname;
  } catch {
    return url;
  }
}

function statusClass(event: OfflineSyncHistory['event']): string {
  if (event === 'synced') return 'badge-success';
  if (event === 'failed') return 'badge-critical';
  return 'badge-warning';
}

export default function OfflineSyncCenter() {
  const { user } = useAuth();
  const [online, setOnline] = useState(() => navigator.onLine);
  const [pending, setPending] = useState<OfflineMutation[]>([]);
  const [history, setHistory] = useState<OfflineSyncHistory[]>([]);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [queue, events] = await Promise.all([getOfflineMutations(), getOfflineSyncHistory(250)]);
      setPending(queue);
      setHistory(events);
    } finally {
      setLoading(false);
    }
  }, []);

  const synchronize = useCallback(async () => {
    if (!navigator.onLine) {
      toast.error('Synchronization requires an active network connection.');
      return;
    }
    setSyncing(true);
    try {
      const result = await syncOfflineMutations();
      await load();
      if (result.synced > 0) toast.success(`${result.synced} queued change${result.synced === 1 ? '' : 's'} synchronized.`);
      else if (result.remaining > 0) toast.warning(`${result.remaining} queued change${result.remaining === 1 ? '' : 's'} remain pending.`);
      else toast.success('Offline queue is synchronized.');
    } finally {
      setSyncing(false);
    }
  }, [load]);

  useEffect(() => {
    const onOnline = () => { setOnline(true); void load(); };
    const onOffline = () => setOnline(false);
    window.addEventListener('online', onOnline);
    window.addEventListener('offline', onOffline);
    const unsubscribe = subscribeToOfflineSync(() => void load());
    void load();
    return () => {
      window.removeEventListener('online', onOnline);
      window.removeEventListener('offline', onOffline);
      unsubscribe();
    };
  }, [load]);

  const failed = useMemo(() => history.filter((item) => item.event === 'failed'), [history]);

  if (user?.role !== 'admin') return <Navigate to="/dashboard" replace />;

  return (
    <div className="space-y-6 animate-fade-in">
      <header className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><History className="w-6 h-6 text-primary" />Offline Synchronization Center</h1>
          <p className="text-muted-foreground">Reconcile this device's queued changes and review synchronization outcomes. This is local browser state, not a substitute for server audit history.</p>
        </div>
        <button type="button" className="btn-primary inline-flex items-center gap-2" onClick={() => void synchronize()} disabled={!online || syncing}>
          <RefreshCw className={`w-4 h-4 ${syncing ? 'animate-spin' : ''}`} />{syncing ? 'Synchronizing…' : 'Synchronize now'}
        </button>
      </header>

      <div className="grid gap-4 md:grid-cols-4">
        <div className="card-medical rounded-2xl p-4"><p className="text-xs text-muted-foreground">Connectivity</p><div className="mt-2 flex items-center gap-2 font-semibold">{online ? <Cloud className="w-5 h-5 text-emerald-600" /> : <CloudOff className="w-5 h-5 text-amber-600" />}{online ? 'Online' : 'Offline'}</div></div>
        <div className="card-medical rounded-2xl p-4"><p className="text-xs text-muted-foreground">Pending</p><p className="mt-2 text-2xl font-bold">{pending.length}</p></div>
        <div className="card-medical rounded-2xl p-4"><p className="text-xs text-muted-foreground">Failed events</p><p className="mt-2 text-2xl font-bold">{failed.length}</p></div>
        <div className="card-medical rounded-2xl p-4"><p className="text-xs text-muted-foreground">History retained</p><p className="mt-2 text-2xl font-bold">{history.length}</p></div>
      </div>

      {!online && <div className="rounded-2xl border border-amber-300/50 bg-amber-50/50 p-4 text-sm flex gap-3"><WifiOff className="w-5 h-5 shrink-0 text-amber-600" /><span>Connectivity is unavailable. Queued work remains on this device and will not be discarded.</span></div>}

      <section className="card-medical rounded-3xl overflow-hidden">
        <div className="p-5 border-b border-border"><h2 className="font-semibold">Pending synchronization queue</h2><p className="text-xs text-muted-foreground mt-1">Payload contents are intentionally not displayed here to reduce unnecessary exposure of clinical data.</p></div>
        {loading ? <div className="p-8 text-center text-muted-foreground">Loading synchronization state…</div> : pending.length === 0 ? <div className="p-8 text-center text-muted-foreground flex flex-col items-center gap-2"><CheckCircle2 className="w-8 h-8 text-emerald-600" />No pending mutations on this device.</div> : <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b border-border text-left"><th className="p-3">Queued</th><th className="p-3">Resource</th><th className="p-3">Method</th><th className="p-3">Attempts</th><th className="p-3">Last error</th></tr></thead><tbody>{pending.map((item) => <tr key={item.id} className="border-b border-border"><td className="p-3 whitespace-nowrap">{new Date(item.createdAt).toLocaleString()}</td><td className="p-3 font-medium">{endpointLabel(item.url)}</td><td className="p-3">{item.method}</td><td className="p-3">{item.attempts}</td><td className="p-3 max-w-md truncate text-muted-foreground">{item.lastError ?? 'Awaiting synchronization'}</td></tr>)}</tbody></table></div>}
      </section>

      <section className="card-medical rounded-3xl overflow-hidden">
        <div className="p-5 border-b border-border flex items-center gap-2"><AlertTriangle className="w-5 h-5 text-primary" /><div><h2 className="font-semibold">Synchronization history</h2><p className="text-xs text-muted-foreground">Queued, synchronized and failed events retained in this browser.</p></div></div>
        {history.length === 0 ? <div className="p-8 text-center text-muted-foreground">No synchronization events recorded yet.</div> : <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b border-border text-left"><th className="p-3">Time</th><th className="p-3">Event</th><th className="p-3">Attempts</th><th className="p-3">HTTP</th><th className="p-3">Error</th></tr></thead><tbody>{history.map((item) => <tr key={item.id} className="border-b border-border"><td className="p-3 whitespace-nowrap">{new Date(item.occurredAt).toLocaleString()}</td><td className="p-3"><span className={statusClass(item.event)}>{item.event}</span></td><td className="p-3">{item.attempts}</td><td className="p-3">{item.status ?? '—'}</td><td className="p-3 max-w-md truncate text-muted-foreground">{item.error ?? '—'}</td></tr>)}</tbody></table></div>}
      </section>
    </div>
  );
}
