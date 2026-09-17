import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { completeServiceOrder, markServiceOrderInProgress, STATUS_LABEL, type ServiceOrderStatus } from '@/lib/workflow';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { CheckCircle2, ClipboardList, PlayCircle, RefreshCw, BellRing } from 'lucide-react';

interface QueueRecord { id: string; department: string; status: string; created_at: string; service_order_id?: string | null; }
interface QueueRow {
  id: string; department: string; status: 'queued' | 'claimed' | 'completed' | 'cancelled'; queued_at: string;
  serviceOrder: { id: string; service_name: string; department: string; amount: number | string; status: ServiceOrderStatus; patient_id: string; patients?: { first_name: string | null; last_name: string | null; patient_code: string | null } | null } | null;
}
type QueueFilter = 'all' | 'queued' | 'claimed';

export default function DepartmentQueue() {
  const { user } = useAuth();
  const [department, setDepartment] = useState<string>('');
  const [rows, setRows] = useState<QueueRow[]>([]);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [filter, setFilter] = useState<QueueFilter>('all');

  const load = useCallback(async () => {
    if (!user?.id) return;
    const { data: profile, error: profileError } = await supabase.from('profiles').select('department').eq('id', user.id).maybeSingle();
    if (profileError) { toast({ title: 'Could not load department', description: profileError.message, variant: 'destructive' }); return; }
    const currentDepartment = profile?.department?.trim() ?? '';
    setDepartment(currentDepartment);
    if (!currentDepartment) { setRows([]); return; }
    const { data: rawQueue, error: queueError } = await supabase.from('department_queues').select('id,department,status,created_at,service_order_id').eq('department', currentDepartment).in('status', ['queued', 'claimed']).order('created_at', { ascending: true });
    if (queueError) { toast({ title: 'Could not load department queue', description: queueError.message, variant: 'destructive' }); return; }
    const queue = (rawQueue ?? []) as unknown as QueueRecord[];
    const orderIds = queue.map((item) => item.service_order_id).filter((id): id is string => Boolean(id));
    if (orderIds.length === 0) { setRows([]); return; }
    const { data: rawOrders, error: orderError } = await supabase.from('service_orders').select('id,service_name,department,amount,status,patient_id,patients(first_name,last_name,patient_code)').in('id', orderIds);
    if (orderError) { toast({ title: 'Could not load queued orders', description: orderError.message, variant: 'destructive' }); return; }
    const orders = (rawOrders ?? []) as unknown as QueueRow['serviceOrder'][];
    const orderMap = new Map(orders.map((order) => [order.id, order]));
    setRows(queue.flatMap((item) => { const serviceOrder = item.service_order_id ? orderMap.get(item.service_order_id) ?? null : null; return serviceOrder ? [{ id: item.id, department: item.department, status: item.status as QueueRow['status'], queued_at: item.created_at, serviceOrder }] : []; }));
  }, [user?.id]);

  useEffect(() => {
    void load();
    if (!user?.id) return;
    const channel = supabase.channel(`department-queue-${user.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'department_queues' }, (payload) => {
        if (payload.eventType === 'INSERT') playWorkflowSound('info');
        if (payload.eventType === 'UPDATE' && (payload.new as { status?: string }).status === 'completed') playWorkflowSound('success');
        void load();
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'service_orders' }, () => void load())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [load, user?.id]);

  const counts = useMemo(() => ({
    active: rows.length,
    queued: rows.filter((row) => row.status === 'queued').length,
    inProgress: rows.filter((row) => row.status === 'claimed').length,
  }), [rows]);

  const visibleRows = useMemo(() => filter === 'all' ? rows : rows.filter((row) => row.status === filter), [filter, rows]);

  const start = async (orderId: string) => {
    setBusyId(orderId);
    try { await markServiceOrderInProgress(orderId); playWorkflowSound('success'); toast({ title: 'Order started' }); await load(); }
    catch (error) { toast({ title: 'Could not start order', description: error instanceof Error ? error.message : 'The order is not available.', variant: 'destructive' }); }
    finally { setBusyId(null); }
  };
  const complete = async (orderId: string) => {
    setBusyId(orderId);
    try { await completeServiceOrder(orderId); playWorkflowSound('success'); toast({ title: 'Order completed', description: 'The patient has been removed from the active queue.' }); await load(); }
    catch (error) { toast({ title: 'Could not complete order', description: error instanceof Error ? error.message : 'The order could not be completed.', variant: 'destructive' }); }
    finally { setBusyId(null); }
  };

  const counterClass = 'card-medical p-4 text-left transition-all hover:-translate-y-0.5 hover:shadow-md focus:outline-none focus:ring-2 focus:ring-primary/30';

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><ClipboardList className="w-6 h-6 text-primary" /> Department Queue</h1><p className="text-muted-foreground">{department ? `Released work for ${department}.` : 'Your profile is not assigned to a department.'}</p></div>
        <div className="flex items-center gap-2"><a href="/notifications" className="btn-secondary inline-flex items-center gap-2"><BellRing className="w-4 h-4" /> Notifications</a><span className="inline-flex items-center gap-1 rounded-full bg-primary/5 px-3 py-1 text-xs text-muted-foreground"><BellRing className="w-3.5 h-3.5" /> Live queue</span><button onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2 self-start"><RefreshCw className="w-4 h-4" /> Refresh</button></div>
      </div>
      {department && <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
        <button type="button" aria-pressed={filter === 'all'} onClick={() => setFilter('all')} className={`${counterClass} bg-warning/5 ${counts.active > 0 ? 'animate-pulse' : ''}`}><p className="text-xs text-muted-foreground">Active patients</p><p className="text-3xl font-bold tabular-nums">{counts.active}</p><p className="mt-1 text-xs text-muted-foreground">Show all active work</p></button>
        <button type="button" aria-pressed={filter === 'queued'} onClick={() => setFilter('queued')} className={`${counterClass} bg-primary/5`}><p className="text-xs text-muted-foreground">Queued</p><p className="text-3xl font-bold tabular-nums">{counts.queued}</p><p className="mt-1 text-xs text-muted-foreground">Waiting to start</p></button>
        <button type="button" aria-pressed={filter === 'claimed'} onClick={() => setFilter('claimed')} className={`${counterClass} bg-info/5`}><p className="text-xs text-muted-foreground">In progress</p><p className="text-3xl font-bold tabular-nums">{counts.inProgress}</p><p className="mt-1 text-xs text-muted-foreground">Currently being attended</p></button>
      </div>}
      {!department && <div className="card-medical p-5 text-sm text-muted-foreground">Ask an administrator to assign your clinical department before using the service queue.</div>}
      {department && visibleRows.length === 0 && <div className="card-medical p-8 text-center text-sm text-muted-foreground">{filter === 'all' ? 'No released service orders are waiting for your department.' : `No ${filter === 'queued' ? 'queued' : 'in-progress'} service orders are currently waiting.`}</div>}
      <div className="space-y-3">{visibleRows.map((row) => { const order = row.serviceOrder; if (!order) return null; const patient = order.patients; const busy = busyId === order.id; return <div key={row.id} className="card-medical p-5 flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between"><div><div className="flex flex-wrap items-center gap-2"><p className="font-semibold">{order.service_name}</p><span className="text-xs rounded-full bg-muted px-2 py-1">{STATUS_LABEL[order.status]}</span></div><p className="text-sm text-muted-foreground">{patient?.first_name} {patient?.last_name} · {patient?.patient_code}</p><p className="text-xs text-muted-foreground mt-1">Queued {new Date(row.queued_at).toLocaleString()}</p></div><div className="flex flex-wrap gap-2">{order.status === 'released' && <button disabled={busy} onClick={() => void start(order.id)} className="btn-primary inline-flex items-center gap-2 disabled:opacity-50"><PlayCircle className="w-4 h-4" /> Start</button>}{order.status === 'in_progress' && <button disabled={busy} onClick={() => void complete(order.id)} className="btn-primary inline-flex items-center gap-2 disabled:opacity-50"><CheckCircle2 className="w-4 h-4" /> Complete</button>}</div></div>; })}</div>
    </div>
  );
}
