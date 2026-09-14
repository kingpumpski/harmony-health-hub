import { useEffect, useState } from 'react';
import { Cloud, CloudOff, RefreshCw } from 'lucide-react';
import { getOfflineMutations, subscribeToOfflineSync, syncOfflineMutations, type OfflineOperationEvent } from '@/lib/offlineSync';

const operationLabel = (kind?: OfflineOperationEvent['kind']) => {
  if (kind === 'vitals') return 'Vital signs';
  if (kind === 'appointment') return 'Appointment';
  if (kind === 'patient') return 'Patient registration';
  if (kind === 'triage') return 'Triage assessment';
  return 'Work';
};

export default function OfflineStatus() {
  const [online, setOnline] = useState(() => navigator.onLine);
  const [pending, setPending] = useState(0);
  const [syncing, setSyncing] = useState(false);
  const [operationMessage, setOperationMessage] = useState<string | null>(null);

  const refresh = async () => setPending((await getOfflineMutations()).length);

  const synchronize = async () => {
    if (!navigator.onLine) return;
    setSyncing(true);
    try { await syncOfflineMutations(); } finally { setSyncing(false); await refresh(); }
  };

  useEffect(() => {
    const onOnline = () => { setOnline(true); void synchronize(); };
    const onOffline = () => setOnline(false);
    const onOperation = (event: Event) => {
      const detail = (event as CustomEvent<OfflineOperationEvent>).detail;
      if (!detail) return;
      if (detail.event === 'queued') {
        setOperationMessage(`${operationLabel(detail.kind)} saved locally and queued for synchronization.`);
      } else if (detail.event === 'synced') {
        setOperationMessage(`${operationLabel(detail.kind)} synchronized with the server.`);
      } else if (detail.event === 'failed') {
        setOperationMessage(`${operationLabel(detail.kind)} is still waiting for synchronization.`);
      }
    };
    window.addEventListener('online', onOnline);
    window.addEventListener('offline', onOffline);
    window.addEventListener('harmony:offline-sync', onOperation);
    const unsubscribe = subscribeToOfflineSync(() => void refresh());
    void refresh();
    void synchronize();
    const retryTimer = window.setInterval(() => void synchronize(), 30000);
    const messageTimer = window.setInterval(() => setOperationMessage(null), 8000);
    return () => {
      window.removeEventListener('online', onOnline);
      window.removeEventListener('offline', onOffline);
      window.removeEventListener('harmony:offline-sync', onOperation);
      unsubscribe();
      window.clearInterval(retryTimer);
      window.clearInterval(messageTimer);
    };
  }, []);

  if (online && pending === 0 && !syncing && !operationMessage) return null;

  return (
    <div className="fixed bottom-4 left-1/2 z-[100] -translate-x-1/2 rounded-full border bg-background/95 px-4 py-2 text-xs shadow-lg backdrop-blur">
      <div className="flex items-center gap-2">
        {online ? <Cloud className="h-4 w-4 text-emerald-600" /> : <CloudOff className="h-4 w-4 text-amber-600" />}
        <span>
          {operationMessage ?? (!online ? 'Offline mode — changes are queued locally.' : syncing ? 'Synchronizing saved work…' : `${pending} change${pending === 1 ? '' : 's'} waiting to sync`)}
        </span>
        {online && pending > 0 && <RefreshCw className={`h-3.5 w-3.5 ${syncing ? 'animate-spin' : ''}`} />}
      </div>
    </div>
  );
}
