import { useEffect, useState } from 'react';
import { Cloud, CloudOff, RefreshCw } from 'lucide-react';
import { getOfflineMutations, subscribeToOfflineSync, syncOfflineMutations } from '@/lib/offlineSync';

export default function OfflineStatus() {
  const [online, setOnline] = useState(() => navigator.onLine);
  const [pending, setPending] = useState(0);
  const [syncing, setSyncing] = useState(false);

  const refresh = async () => {
    setPending((await getOfflineMutations()).length);
  };

  useEffect(() => {
    const onOnline = async () => {
      setOnline(true);
      setSyncing(true);
      try { await syncOfflineMutations(); } finally { setSyncing(false); await refresh(); }
    };
    const onOffline = () => setOnline(false);
    window.addEventListener('online', onOnline);
    window.addEventListener('offline', onOffline);
    const unsubscribe = subscribeToOfflineSync(refresh);
    void refresh();
    return () => {
      window.removeEventListener('online', onOnline);
      window.removeEventListener('offline', onOffline);
      unsubscribe();
    };
  }, []);

  if (online && pending === 0 && !syncing) return null;

  return (
    <div className="fixed bottom-4 left-1/2 z-[100] -translate-x-1/2 rounded-full border bg-background/95 px-4 py-2 text-xs shadow-lg backdrop-blur">
      <div className="flex items-center gap-2">
        {online ? <Cloud className="h-4 w-4 text-emerald-600" /> : <CloudOff className="h-4 w-4 text-amber-600" />}
        <span>
          {!online ? 'Offline mode — changes are queued locally.' : syncing ? 'Synchronizing saved work…' : `${pending} change${pending === 1 ? '' : 's'} waiting to sync`}
        </span>
        {online && pending > 0 && <RefreshCw className={`h-3.5 w-3.5 ${syncing ? 'animate-spin' : ''}`} />}
      </div>
    </div>
  );
}
