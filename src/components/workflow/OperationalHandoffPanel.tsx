import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, Bell, CheckCircle2, Info, MessageSquare, RefreshCw } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { cn } from '@/lib/utils';

type NotificationRow = {
  id: string;
  title: string;
  message: string;
  severity: string;
  category: string | null;
  link: string | null;
  is_read: boolean;
  created_at: string;
};

const roleLabels: Record<string, string> = {
  admin: 'facility operations',
  practitioner: 'clinical care',
  nurse: 'nursing care',
  midwife: 'maternity care',
  specialist_nurse: 'specialist nursing',
  lab_technician: 'laboratory',
  radiologist: 'radiology',
  radiology_technician: 'imaging',
  pharmacist: 'pharmacy',
  accountant: 'finance',
  front_desk: 'front desk',
  canteen: 'dietary services',
  patient: 'your care',
  it_admin: 'technology support',
};

const severityIcon = (severity: string) => {
  if (severity === 'critical') return <AlertTriangle className="h-4 w-4 text-critical" aria-hidden="true" />;
  if (severity === 'warning') return <Bell className="h-4 w-4 text-warning" aria-hidden="true" />;
  if (severity === 'success') return <CheckCircle2 className="h-4 w-4 text-success" aria-hidden="true" />;
  return <Info className="h-4 w-4 text-info" aria-hidden="true" />;
};

export default function OperationalHandoffPanel() {
  const { user } = useAuth();
  const [items, setItems] = useState<NotificationRow[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    const { data, error } = await (supabase as any).rpc('get_workflow_notifications', { _limit: 25 });
    if (!error) setItems((Array.isArray(data) ? data : []) as NotificationRow[]);
    else setItems([]);
    setLoading(false);
  }, [user]);

  useEffect(() => {
    void load();
    // Poll through the server-scoped RPC rather than subscribing to the raw
    // notifications table. This prevents realtime payloads from bypassing the
    // role/facility filtering enforced by get_workflow_notifications().
    const timer = window.setInterval(() => void load(), 60000);
    return () => window.clearInterval(timer);
  }, [load]);

  const unread = useMemo(() => items.filter((item) => !item.is_read), [items]);
  const critical = useMemo(() => unread.filter((item) => item.severity === 'critical'), [unread]);
  const recent = useMemo(() => unread.slice(0, 3), [unread]);
  const roleLabel = roleLabels[user?.role ?? ''] ?? 'your operations';

  if (!user || (!loading && !items.length)) return null;

  return (
    <section className="card-medical overflow-hidden border-primary/20 bg-primary/[0.025]" aria-labelledby="operational-handoff-heading">
      <div className="flex flex-col gap-3 border-b border-border p-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex min-w-0 items-start gap-3">
          <div className="rounded-xl bg-primary/10 p-2 text-primary"><MessageSquare className="h-5 w-5" aria-hidden="true" /></div>
          <div className="min-w-0">
            <h2 id="operational-handoff-heading" className="font-semibold">Shared workflow communication</h2>
            <p className="text-xs text-muted-foreground">Role-scoped handoffs and operational alerts for {roleLabel}.</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {critical.length > 0 && <span className="rounded-full bg-critical/10 px-2.5 py-1 text-xs font-semibold text-critical">{critical.length} critical</span>}
          <span className="rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">{unread.length} unread</span>
          <button type="button" onClick={() => void load()} className="btn-ghost" aria-label="Refresh shared workflow communication">
            <RefreshCw className={cn('h-4 w-4', loading && 'animate-spin motion-reduce:animate-none')} aria-hidden="true" />
          </button>
          <Link to="/notifications" className="btn-secondary text-xs">Open communication center</Link>
        </div>
      </div>

      {loading && (
        <div className="space-y-2 p-4" role="status" aria-live="polite">
          <div className="h-12 animate-pulse rounded-lg bg-muted motion-reduce:animate-none" />
          <div className="h-12 animate-pulse rounded-lg bg-muted motion-reduce:animate-none" />
        </div>
      )}

      {!loading && recent.length > 0 && (
        <div className="divide-y divide-border">
          {recent.map((item) => {
            const row = (
              <div className={cn('flex items-start gap-3 p-4 transition-colors hover:bg-muted/30', item.severity === 'critical' && 'border-l-2 border-l-critical bg-critical/5')}>
                {severityIcon(item.severity)}
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{item.title}</p>
                  <p className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">{item.message}</p>
                  <p className="mt-1 text-[10px] uppercase tracking-wider text-muted-foreground">
                    {item.category ?? 'workflow'} · {new Date(item.created_at).toLocaleString()}
                  </p>
                </div>
              </div>
            );
            return item.link
              ? <Link key={item.id} to={item.link}>{row}</Link>
              : <div key={item.id}>{row}</div>;
          })}
        </div>
      )}

      {!loading && recent.length === 0 && unread.length === 0 && (
        <div className="p-5 text-center text-sm text-muted-foreground">No unread workflow communication.</div>
      )}
    </section>
  );
}
