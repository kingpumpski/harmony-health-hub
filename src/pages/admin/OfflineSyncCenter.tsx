import { useCallback, useEffect, useMemo, useState } from 'react';
import { Navigate } from 'react-router-dom';
import { AlertTriangle, CheckCircle2, Cloud, CloudOff, History, RefreshCw, WifiOff, RotateCcw } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import {
  getOfflineMutations,
  getOfflineReadModels,
  getOfflineSyncHistory,
  retryOfflineMutation,
  syncOfflineMutations,
  subscribeToOfflineSync,
  type OfflineMutation,
  type OfflineReadModel,
  type OfflineSyncHistory,
} from '@/lib/offlineSync';

function endpointLabel(url: string): string {
  try {
    const parsed = new URL(url);
    const match = parsed.pathname.match(/\/rest\/v1\/([^/]+)/);
    if (match?.[1]) return match[1];
    const rpc = parsed.pathname.match(/\/rpc\/([^/]+)/);
    return rpc?.[1] ? `RPC · ${rpc[1]}` : parsed.pathname;
  } catch {
    return url;
  }
}

function statusClass(event: OfflineSyncHistory['event']): string {
  if (event === 'synced') return 'badge-success';
  if (event === 'failed') return 'badge-critical';
  return 'badge-warning';
}

function continuityLabel(item: OfflineReadModel): string {
  if (item.kind === 'patient') return `${String(item.data.first_name ?? '')} ${String(item.data.last_name ?? '')}`.trim() || String(item.data.patient_code ?? item.id);
  if (item.kind === 'triage') return `Triage · ${String(item.data.patient_id ?? item.id)}`;
  if (item.kind === 'vitals') return `Vitals · ${String(item.data.patient_id ?? item.id)}`;
  return `Appointment · ${String(item.data._patient_id ?? item.data.patient_id ?? item.id)}`;
}

function retryLabel(item: OfflineMutation): string {
  if (item.status === 'blocked') return 'Blocked — manual retry required';
  if (item.nextAttemptAt) {
    const next = new Date(item.nextAttemptAt);
    if (next.getTime() > Date.now()) return `Retry after ${next.toLocaleTimeString()}`;
  }
  return 'Ready for synchronization';
}

export default function OfflineSyncCenter() {
  const { user } = useAuth();
  const [online, setOnline] = useState(() => navigator.onLine);
  const [pending, setPending] = useState<OfflineMutation[]>([]);
  const [history, setHistory] = useState<OfflineSyncHistory[]>([]);
  const [continuity, setContinuity] = useState<OfflineReadModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [retryingId, setRetryingId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [queue, events, records] = await Promise.all([
        getOfflineMutations(),
        getOfflineSyncHistory(250),
        getOfflineReadModels(undefined, 100),
      ]);
      setPending(queue);
      setHistory(events);
      setContinuity(records);
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
      else if (result.blocked > 0) toast.warning(`${result.blocked} queued change${result.blocked === 1 ? '' : 's'} require manual retry.`);
      else if (result.remaining > 0) toast.warning(`${result.remaining} queued change${result.remaining === 1 ? '' : 's'} remain pending.`);
      else toast.success('Offline queue is synchronized.');
    } finally {
      setSyncing(false);
    }
  }, [load]);

  const retry = useCallback(async (id: string) => {
    setRetryingId(id);
    try {
      const changed = await retryOfflineMutation(id);
      if (!changed) {
        toast.error('The queued mutation is no longer available.');
        return;
      }
      await load();
      if (navigator.onLine) {
        const result = await syncOfflineMutations();
        await load();
        if (result.synced > 0) toast.success('Queued change synchronized successfully.');
        else toast.info('Queued change was released for retry and remains pending.');
      } else {
        toast.success('Queued change released. It will retry when connectivity returns.');
      }
    } finally {
      setRetryingId(null);
    }
  }, [load]);

  useEffect(() => {
    const onOnline = () => {
      setOnline(true);
      void load();
    };
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
  const blocked = useMemo(() => pending.filter((item) => item.status === 'blocked'), [pending]);

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

      <div className="grid gap-4 md:grid-cols-5">
        <div className="card-medical rounded-2xl p-4"><p className="text-xs text-muted-foreground">Connectivity</p><div className="mt-2 flex items-center gap-2 font-semibold">{online ? <Cloud className="w-5 h-5 text-emerald-600" /> : <CloudOff className="w-5 h-5 text-amber-600" />}{online ? 'Online' : 'Offline'}</div></div>
        <div className="card-medical rounded-2xl p-4"><p className="text-xs text-muted-foreground">Pending</p><p className="mt-2 text-2xl font-bold">{pending.length}</p></div>
        <div className="card-medical rounded-2xl p-4"><p className="text-xs text-muted-foreground">Blocked</p><p className="mt-2 text-2xl font-bold">{blocked.length}</p></div>
        <div className="card-medical rounded-2xl p-4"><p className="text-xs text-muted-foreground">Failed events</p><p className="mt-2 text-2xl font-bold">{failed.length}</p></div>
        <div className="card-medical rounded-2xl p-4"><p className="text-xs text-muted-foreground">Continuity records</p><p className="mt-2 text-2xl font-bold">{continuity.length}</p></div>
      </div>

      {!online && <div className="rounded-2xl border border-amber-300/50 bg-amber-50/50 p-4 text-sm flex gap-3"><WifiOff className="w-5 h-5 shrink-0 text-amber-600" /><span>Connectivity is unavailable. Queued work remains on this device and will not be discarded.</span></div>}
      {blocked.length > 0 && <div className="rounded-2xl border border-red-300/50 bg-red-50/50 p-4 text-sm flex gap-3"><AlertTriangle className="w-5 h-5 shrink-0 text-red-600" /><span>{blocked.length} queued change{blocked.length === 1 ? '' : 's'} reached a non-transient server response and are blocked from automatic retry. Review the error below and use <strong>Retry</strong> only after the underlying issue is understood.</span></div>}

      <section className="card-medical rounded-3xl overflow-hidden">
        <div className="p-5 border-b border-border"><h2 className="font-semibold">Offline continuity records</h2><p className="text-xs text-muted-foreground mt-1">Patient registration, triage, selected vital signs and appointment records remain visible while disconnected. Status changes to server-confirmed only after successful synchronization.</p></div>
        {loading ? <div className="p-8 text-center text-muted-foreground">Loading continuity records…</div> : continuity.length === 0 ? <div className="p-8 text-center text-muted-foreground">No offline continuity records on this device.</div> : <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b border-border text-left"><th className="p-3">Created</th><th className="p-3">Type</th><th className="p-3">Record</th><th className="p-3">Status</th></tr></thead><tbody>{continuity.map((item) => <tr key={item.id} className="border-b border-border"><td className="p-3 whitespace-nowrap">{new Date(item.createdAt).toLocaleString()}</td><td className="p-3 capitalize">{item.kind}</td><td className="p-3 font-medium">{continuityLabel(item)}</td><td className="p-3"><span className={item.status === 'server-confirmed' ? 'badge-success' : 'badge-warning'}>{item.status === 'server-confirmed' ? 'Server confirmed' : 'Queued locally'}</span></td></tr>)}</tbody></table></div>}
      </section>

      <section className="card-medical rounded-3xl overflow-hidden">
        <div className="p-5 border-b border-border"><h2 className="font-semibold">Pending synchronization queue</h2><p className="text-xs text-muted-foreground mt-1">Payload contents are intentionally not displayed here to reduce unnecessary exposure of clinical data. Transient failures use backoff; permanent/conflict responses are blocked until manually released.</p></div>
        {loading ? <div className="p-8 text-center text-muted-foreground">Loading synchronization state…</div> : pending.length === 0 ? <div className="p-8 text-center text-muted-foreground flex flex-col items-center gap-2"><CheckCircle2 className="w-8 h-8 text-emerald-600" />No pending mutations on this device.</div> : <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b border-border text-left"><th className="p-3">Queued</th><th className="p-3">Resource</th><th className="p-3">Method</th><th className="p-3">State</th><th className="p-3">Attempts</th><th className="p-3">Retry</th><th className="p-3">Last error</th><th className="p-3">Action</th></tr></thead><tbody>{pending.map((item) => <tr key={item.id} className="border-b border-border"><td className="p-3 whitespace-nowrap">{new Date(item.createdAt).toLocaleString()}</td><td className="p-3 font-medium">{endpointLabel(item.url)}</td><td className="p-3">{item.method}</td><td className="p-3"><span className={item.status === 'blocked' ? 'badge-critical' : 'badge-warning'}>{item.status === 'blocked' ? 'Blocked' : 'Pending'}</span></td><td className="p-3">{item.attempts}</td><td className="p-3 whitespace-nowrap text-muted-foreground">{retryLabel(item)}</td><td className="p-3 max-w-md truncate text-muted-foreground">{item.lastError ?? 'Awaiting synchronization'}</td><td className="p-3">{item.status === 'blocked' && <button type="button" className="btn-secondary inline-flex items-center gap-2" onClick={() => void retry(item.id)} disabled={retryingId === item.id}><RotateCcw className={`w-4 h-4 ${retryingId === item.id ? 'animate-spin' : ''}`} />{retryingId === item.id ? 'Retrying…' : 'Retry'}</button>}</td></tr>)}</tbody></table></div>}
      </section>

      <section className="card-medical rounded-3xl overflow-hidden">
        <div className="p-5 border-b border-border flex items-center gap-2"><AlertTriangle className="w-5 h-5 text-primary" /><div><h2 className="font-semibold">Synchronization history</h2><p className="text-xs text-muted-foreground">Queued, synchronized and failed events retained in this browser.</p></div></div>
        {history.length === 0 ? <div className="p-8 text-center text-muted-foreground">No synchronization events recorded yet.</div> : <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b border-border text-left"><th className="p-3">Time</th><th className="p-3">Event</th><th className="p-3">Attempts</th><th className="p-3">HTTP</th><th className="p-3">Error</th></tr></thead><tbody>{history.map((item) => <tr key={item.id} className="border-b border-border"><td className="p-3 whitespace-nowrap">{new Date(item.occurredAt).toLocaleString()}</td><td className="p-3"><span className={statusClass(item.event)}>{item.event}</span></td><td className="p-3">{item.attempts}</td><td className="p-3">{item.status ?? '—'}</td><td className="p-3 max-w-md truncate text-muted-foreground">{item.error ?? '—'}</td></tr>)}</tbody></table></div>}
      </section>
    </div>
  );
}
