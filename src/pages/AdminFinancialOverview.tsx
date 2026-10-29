import { useCallback, useEffect, useState } from 'react';
import { RefreshCw, ShieldCheck } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import RouteLoadingScreen from '@/components/system/RouteLoadingScreen';

type Summary = { nhis_pending_count: number; cash_collected_today: number; currency: string };

export default function AdminFinancialOverview() {
  const { user } = useAuth();
  const [summary, setSummary] = useState<Summary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_billing_workspace_summary');
      if (rpcError) throw rpcError;
      const row = Array.isArray(data) ? data[0] : data;
      if (!row) throw new Error('The financial overview returned no summary.');
      setSummary(row as Summary);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Unable to load the financial overview.');
      setSummary(null);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);
  if (loading && !summary) return <RouteLoadingScreen />;

  return <main className="space-y-6 p-4 sm:p-6" aria-labelledby="financial-overview-title">
    <header className="flex flex-wrap items-start justify-between gap-3">
      <div>
        <div className="flex items-center gap-2 text-sm text-muted-foreground"><ShieldCheck className="h-4 w-4" /> Read-only oversight</div>
        <h1 id="financial-overview-title" className="mt-1 text-2xl font-semibold">Financial Overview</h1>
        <p className="mt-1 max-w-2xl text-sm text-muted-foreground">Facility-level financial indicators for oversight. Invoice editing, payment collection, tariff changes and claim processing are not available in this view.</p>
      </div>
      <button type="button" className="btn-secondary inline-flex items-center gap-2" onClick={() => void load()} disabled={loading} aria-label="Refresh financial overview" title="Refresh financial overview">
        <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
      </button>
    </header>
    {error && <section role="alert" className="rounded-xl border border-warning/40 bg-warning/5 p-4"><p className="text-sm font-medium">Financial overview unavailable</p><p className="mt-1 text-sm text-muted-foreground">{error}</p><button className="btn-secondary mt-3" onClick={() => void load()}>Retry</button></section>}
    <section className="grid gap-4 sm:grid-cols-2" aria-label="Financial overview metrics">
      <article className="rounded-xl border border-border bg-card p-5">
        <p className="text-sm text-muted-foreground">Cash collected today</p>
        <p className="mt-2 text-2xl font-semibold tabular-nums">{summary ? `${summary.currency || 'GHS'} ${Number(summary.cash_collected_today || 0).toFixed(2)}` : '—'}</p>
        <p className="mt-1 text-xs text-muted-foreground">Completed cash payments for the active facility.</p>
      </article>
      <article className="rounded-xl border border-border bg-card p-5">
        <p className="text-sm text-muted-foreground">NHIS claims pending</p>
        <p className="mt-2 text-2xl font-semibold tabular-nums">{summary ? Number(summary.nhis_pending_count || 0).toLocaleString() : '—'}</p>
        <p className="mt-1 text-xs text-muted-foreground">Claims requiring follow-up; individual claim records are not shown.</p>
      </article>
    </section>
    <p className="text-xs text-muted-foreground">Signed in as {user?.role === 'it_admin' ? 'IT administrator' : user?.role === 'system_superuser' ? 'platform superuser' : 'administrator'}. This screen does not provide financial settlement controls.</p>
  </main>;
}
