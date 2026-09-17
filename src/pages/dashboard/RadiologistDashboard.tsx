import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { AlertTriangle, BellRing, CheckCircle2, Clock3, Image as ImageIcon, Loader2, RefreshCw } from 'lucide-react';

interface ImagingOrder { id: string; patient_id: string; study_name: string; modality: string; priority: string; status: string; created_at: string; patients?: { first_name: string; last_name: string } | null }
const statusKeys = ['awaiting', 'ready', 'in_progress', 'completed', 'urgent'] as const;
type StatusKey = typeof statusKeys[number];

export default function RadiologistDashboard() {
  const [orders, setOrders] = useState<ImagingOrder[]>([]);
  const [unreadAlerts, setUnreadAlerts] = useState(0);
  const [loading, setLoading] = useState(false);
  const [previousIds, setPreviousIds] = useState<Set<string>>(new Set());
  const load = async (announce = false) => {
    setLoading(true);
    const [{ data: imaging }, { data: notifications }] = await Promise.all([
      supabase.from('imaging_orders').select('id,patient_id,study_name,modality,priority,status,created_at,patients(first_name,last_name)').order('created_at', { ascending: false }).limit(100),
      supabase.from('notifications').select('id').eq('is_read', false).eq('severity', 'critical'),
    ]);
    const next = (imaging ?? []) as ImagingOrder[];
    if (announce && previousIds.size > 0 && next.some((order) => !previousIds.has(order.id))) playWorkflowSound('info');
    setPreviousIds(new Set(next.map((order) => order.id)));
    setOrders(next); setUnreadAlerts(notifications?.length ?? 0); setLoading(false);
  };
  useEffect(() => { void load(); }, []);
  useEffect(() => {
    const channel = supabase.channel('radiologist-dashboard-live')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'imaging_orders' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, (payload) => { if (payload.eventType === 'INSERT' && String((payload.new as { severity?: string }).severity ?? '').toLowerCase() === 'critical') playWorkflowSound('critical'); void load(); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'service_orders' }, () => void load())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, []);
  const counters = useMemo<Record<StatusKey, number>>(() => ({ awaiting: orders.filter((o) => ['pending_payment_approval', 'pending_payment'].includes(o.status)).length, ready: orders.filter((o) => ['released', 'queued'].includes(o.status)).length, in_progress: orders.filter((o) => o.status === 'in_progress').length, completed: orders.filter((o) => o.status === 'completed').length, urgent: orders.filter((o) => ['urgent', 'stat'].includes(o.priority) && o.status !== 'completed').length }), [orders]);
  const activeQueue = useMemo(() => orders.filter((o) => o.status !== 'completed').slice(0, 8), [orders]);
  const cards = [
    { key: 'awaiting' as StatusKey, label: 'Awaiting Accounts', icon: Clock3, tone: 'text-warning', surface: 'bg-warning/5' },
    { key: 'ready' as StatusKey, label: 'Ready for Imaging', icon: ImageIcon, tone: 'text-info', surface: 'bg-info/5' },
    { key: 'in_progress' as StatusKey, label: 'In Progress', icon: Loader2, tone: 'text-primary', surface: 'bg-primary/5' },
    { key: 'completed' as StatusKey, label: 'Completed', icon: CheckCircle2, tone: 'text-success', surface: 'bg-success/5' },
    { key: 'urgent' as StatusKey, label: 'Urgent / STAT', icon: AlertTriangle, tone: 'text-critical', surface: 'bg-critical/5' },
  ];
  return <div className="space-y-6 animate-fade-in">
    <header className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h1 className="flex items-center gap-2 text-2xl font-heading font-bold"><ImageIcon className="h-6 w-6 text-primary" /> Radiologist Dashboard</h1><p className="text-muted-foreground">Live diagnostic imaging worklist, reporting and urgent-case monitoring.</p></div><div className="flex items-center gap-2"><Link to="/notifications" className="btn-secondary inline-flex items-center gap-2"><BellRing className="h-4 w-4" /> Alerts {unreadAlerts > 0 && <span className="rounded-full bg-critical px-2 py-0.5 text-xs text-critical-foreground">{unreadAlerts}</span>}</Link><button type="button" onClick={() => { playWorkflowSound('info'); void load(); }} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="h-4 w-4" />{loading ? 'Refreshing…' : 'Refresh'}</button></div></header>
    <section className="grid grid-cols-2 gap-3 lg:grid-cols-5">{cards.map((card) => { const Icon = card.icon; return <Link key={card.key} to="/radiology" className={`card-medical p-4 transition-all hover:-translate-y-1 ${card.surface}`}><div className="flex items-center justify-between"><p className="text-xs text-muted-foreground">{card.label}</p><Icon className={`h-4 w-4 ${card.tone}`} /></div><p className={`mt-1 text-3xl font-bold ${card.tone} ${counters[card.key] > 0 && card.key !== 'completed' ? 'animate-pulse' : ''}`}>{counters[card.key]}</p><p className="mt-1 text-xs text-muted-foreground">Open worklist</p></Link>; })}</section>
    {counters.urgent > 0 && <div className="flex items-center gap-2 rounded-xl border border-critical/30 bg-critical/5 p-3 text-sm"><BellRing className="h-4 w-4 text-critical" /><span className="font-medium">{counters.urgent} urgent/STAT case{counters.urgent === 1 ? '' : 's'} require radiology attention.</span><Link to="/radiology" className="ml-auto font-medium text-primary">Open queue</Link></div>}
    <section className="card-medical overflow-hidden"><div className="flex items-center justify-between border-b border-border p-5"><div><h2 className="font-semibold">Active Radiology Queue</h2><p className="text-xs text-muted-foreground">Cases are synchronized with the imaging workflow.</p></div><Link to="/department-queue" className="btn-ghost text-sm">Department Queue →</Link></div><div className="divide-y divide-border">{activeQueue.map((order) => { const urgent = ['urgent', 'stat'].includes(order.priority); return <Link key={order.id} to="/radiology" className={`flex items-center justify-between gap-4 p-4 transition-colors hover:bg-muted/30 ${urgent ? 'bg-critical/5' : ''}`}><div className="min-w-0"><p className="truncate font-medium">{order.study_name} · {order.modality}</p><p className="text-xs text-muted-foreground">{order.patients?.first_name} {order.patients?.last_name} · {order.priority} · {new Date(order.created_at).toLocaleString()}</p></div><div className="flex shrink-0 items-center gap-2"><span className="rounded-full bg-muted px-2 py-1 text-xs font-medium">{order.status}</span>{urgent && <AlertTriangle className="h-4 w-4 text-critical" />}</div></Link>; })}{activeQueue.length === 0 && <div className="p-8 text-center text-sm text-muted-foreground">No active imaging cases.</div>}</div></section>
    <section className="grid gap-3 sm:grid-cols-3"><Link to="/radiology" className="card-medical p-4 hover:-translate-y-1 transition-transform"><p className="font-medium">Imaging Worklist</p><p className="mt-1 text-sm text-muted-foreground">Start released studies and complete radiology reports.</p></Link><Link to="/patients" className="card-medical p-4 hover:-translate-y-1 transition-transform"><p className="font-medium">Patient Records</p><p className="mt-1 text-sm text-muted-foreground">Review patient information linked to imaging cases.</p></Link><Link to="/notifications" className="card-medical p-4 hover:-translate-y-1 transition-transform"><p className="font-medium">Notifications</p><p className="mt-1 text-sm text-muted-foreground">Review critical and workflow alerts.</p></Link></section>
  </div>;
}
