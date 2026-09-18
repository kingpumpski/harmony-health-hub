import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { useAuth } from '@/contexts/AuthContext';
import { AlertTriangle, CheckCircle2, Image as ImageIcon, RefreshCw } from 'lucide-react';
import { toast } from '@/hooks/use-toast';

interface ResultRow {
  id: string;
  patient_id: string;
  study_name: string;
  modality: string;
  priority: string;
  report: string | null;
  impression: string | null;
  encounter_id: string | null;
  created_at: string;
  updated_at: string;
  patients?: { first_name: string; last_name: string } | null;
}
interface ResultNotification { id: string; related_entity_id: string | null; is_read: boolean }

export default function ClinicalResults() {
  const { user } = useAuth();
  const [results, setResults] = useState<ResultRow[]>([]);
  const [notifications, setNotifications] = useState<ResultNotification[]>([]);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    if (!user?.id) return;
    setLoading(true);
    const [{ data: imaging }, { data: notes }] = await Promise.all([
      supabase.from('imaging_orders').select('id,patient_id,study_name,modality,priority,report,impression,encounter_id,created_at,updated_at,patients(first_name,last_name)').eq('requested_by', user.id).eq('status', 'completed').order('updated_at', { ascending: false }).limit(100),
      (supabase as any).rpc('get_workflow_notifications', { _limit: 200 }),
    ]);
    setResults((imaging ?? []) as ResultRow[]);
    setNotifications((notes ?? []) as ResultNotification[]);
    setLoading(false);
  }, [user?.id]);

  useEffect(() => {
    void load();
    if (!user?.id) return;
    const channel = supabase.channel(`clinical-results-${user.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'imaging_orders' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, () => void load())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [load, user?.id]);

  const unreadResultIds = useMemo(() => new Set(notifications.map((n) => n.related_entity_id).filter(Boolean) as string[]), [notifications]);

  const acknowledge = async (resultId: string) => {
    const matching = notifications.filter((n) => n.related_entity_id === resultId);
    if (!matching.length) return;
    const { error } = await (supabase as any).rpc('mark_notifications_read', { _notification_ids: matching.map((n) => n.id) });
    if (error) {
      playWorkflowSound('critical');
      toast({ title: 'Could not acknowledge result', description: error.message, variant: 'destructive' });
      return;
    }
    playWorkflowSound('success');
    toast({ title: 'Radiology result acknowledged' });
    void load();
  };

  if (!user) return null;
  return <div className="space-y-6 animate-fade-in">
    <header className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><ImageIcon className="w-6 h-6 text-primary" /> Radiology Results Review</h1><p className="text-muted-foreground">Review completed diagnostic imaging reports assigned to you and acknowledge each result.</p></div>
      <button type="button" onClick={() => { playWorkflowSound('info'); void load(); }} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="w-4 h-4" />{loading ? 'Refreshing…' : 'Refresh'}</button>
    </header>
    <section className="grid grid-cols-2 gap-3 sm:grid-cols-3"><div className="card-medical bg-warning/5 p-4"><p className="text-xs text-muted-foreground">Results to review</p><p className="mt-1 text-3xl font-bold text-warning">{results.filter((r) => unreadResultIds.has(r.id)).length}</p></div><div className="card-medical bg-success/5 p-4"><p className="text-xs text-muted-foreground">Completed results</p><p className="mt-1 text-3xl font-bold text-success">{results.length}</p></div></section>
    <div className="card-medical divide-y divide-border overflow-hidden">
      {results.length === 0 && <div className="p-8 text-center text-sm text-muted-foreground">No completed radiology results have been assigned to you.</div>}
      {results.map((result) => { const unread = unreadResultIds.has(result.id); const urgent = ['urgent', 'stat'].includes(result.priority.toLowerCase()); return <article key={result.id} className={`p-5 space-y-4 ${unread ? 'bg-primary/5' : ''}`}>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><div className="flex items-center gap-2"><h2 className="font-semibold">{result.study_name} · {result.modality}</h2>{urgent && <AlertTriangle className="w-4 h-4 text-critical" />}</div><p className="text-sm text-muted-foreground">{result.patients?.first_name} {result.patients?.last_name} · {result.priority} · Completed {new Date(result.updated_at).toLocaleString()}</p></div>{unread ? <button type="button" onClick={() => void acknowledge(result.id)} className="btn-primary inline-flex items-center gap-2 text-xs"><CheckCircle2 className="w-4 h-4" />Acknowledge result</button> : <span className="badge-success">Acknowledged</span>}</div>
        <div className="grid gap-3 md:grid-cols-2"><div className="rounded-xl border border-border p-4"><p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Radiology report</p><p className="mt-2 whitespace-pre-wrap text-sm">{result.report || 'No narrative report entered.'}</p></div><div className="rounded-xl border border-primary/20 bg-primary/5 p-4"><p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Impression</p><p className="mt-2 whitespace-pre-wrap text-sm font-medium">{result.impression || 'No impression entered.'}</p></div></div>
      </article>; })}
    </div>
  </div>;
}
