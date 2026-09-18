import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { cancelServiceOrder, grantServiceOrderOverride, releaseServiceOrder, getPaymentFlow, setPaymentFlow, STATUS_LABEL, type PaymentFlow, type ServiceOrderStatus } from '@/lib/workflow';
import { BadgeCheck, Banknote, ShieldCheck, XCircle, Settings2, Clock3, Activity, CheckCircle2, LogOut, ReceiptText } from 'lucide-react';
import { playWorkflowSound } from '@/lib/workflowFeedback';

interface AccountsOrder { id: string; patient_id: string; service_name: string; department: string; amount: number | string; status: ServiceOrderStatus; invoice_id: string | null; patients?: { first_name: string | null; last_name: string | null; patient_code: string | null; insurance_provider: string | null; insurance_number: string | null } | null; }
interface WorkflowCounts { pending: number; released: number; inProgress: number; completed: number; discharged: number; }
interface NotificationRowLike { id: string; message: string; title: string; category: string | null; is_read: boolean; created_at: string; related_patient_id: string | null; related_entity_id: string | null; }
interface DischargeNotice { id: string; message: string; created_at: string; related_patient_id: string | null; related_entity_id: string | null; }
interface Reconciliation { notificationId: string; gross: number; paid: number; outstanding: number; insuranceClaimed: number; insurancePaid: number; status: string; patientId: string; }
const initialCounts: WorkflowCounts = { pending: 0, released: 0, inProgress: 0, completed: 0, discharged: 0 };
const money = (value: number) => `GHS ${Number(value || 0).toFixed(2)}`;

export default function AccountsApprovals() {
  const { user } = useAuth();
  const [orders, setOrders] = useState<AccountsOrder[]>([]);
  const [counts, setCounts] = useState<WorkflowCounts>(initialCounts);
  const [flow, setFlow] = useState<PaymentFlow>('streamlined');
  const [filter, setFilter] = useState<ServiceOrderStatus>('pending_payment_approval');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [dischargeNotices, setDischargeNotices] = useState<DischargeNotice[]>([]);
  const [reconciliations, setReconciliations] = useState<Record<string, Reconciliation>>({});
  const isAdmin = user?.role === 'admin';

  const load = useCallback(async () => {
    const [filtered, summary, notices] = await Promise.all([
      supabase.from('service_orders').select('id,patient_id,service_name,department,amount,status,invoice_id,patients(first_name,last_name,patient_code,insurance_provider,insurance_number)').eq('status', filter).order('created_at', { ascending: false }).limit(100),
      supabase.from('service_orders').select('status').in('status', ['pending_payment_approval', 'released', 'in_progress', 'completed']),
      (supabase as any).rpc('get_workflow_notifications', { _limit: 200 }),
    ]);
    if (filtered.error) { toast({ title: 'Could not load approvals', description: filtered.error.message, variant: 'destructive' }); return; }
    const rows = (summary.data ?? []) as Array<{ status: ServiceOrderStatus }>;
    const workflowNotices = ((notices.data ?? []) as NotificationRowLike[]).filter((n) => !n.is_read && n.category === 'payment' && n.title === 'Discharged patient ready for billing reconciliation');
    setCounts({ pending: rows.filter((r) => r.status === 'pending_payment_approval').length, released: rows.filter((r) => r.status === 'released').length, inProgress: rows.filter((r) => r.status === 'in_progress').length, completed: rows.filter((r) => r.status === 'completed').length, discharged: workflowNotices.length });
    setDischargeNotices(workflowNotices.map((n) => ({ id: n.id, message: n.message, created_at: n.created_at, related_patient_id: n.related_patient_id, related_entity_id: n.related_entity_id })));
    setOrders((filtered.data ?? []) as AccountsOrder[]);
  }, [filter]);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => { getPaymentFlow().then(setFlow).catch((error: Error) => toast({ title: 'Could not load routing settings', description: error.message, variant: 'destructive' })); }, []);
  useEffect(() => {
    const channel = supabase.channel(`accounts-approvals-${user?.id ?? 'guest'}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'service_orders' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, (payload) => { const row = payload.new as { category?: string; severity?: string; recipient_role?: string; title?: string }; if (row.category === 'payment' || row.severity === 'critical') playWorkflowSound(row.severity === 'critical' ? 'critical' : 'warning'); if (row.title === 'Discharged patient ready for billing reconciliation') playWorkflowSound('warning'); void load(); })
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [load, user?.id]);

  const approve = async (order: AccountsOrder) => { setBusyId(order.id); try { await releaseServiceOrder(order.id, user?.id); playWorkflowSound('success'); toast({ title: 'Released to department', description: `${order.service_name} is now open for work.` }); await load(); } catch (error) { playWorkflowSound('critical'); toast({ title: 'Release blocked', description: error instanceof Error ? error.message : 'Payment approval is required.', variant: 'destructive' }); } finally { setBusyId(null); } };
  const override = async (order: AccountsOrder) => { const reason = window.prompt('Enter the Accounts override reason:')?.trim(); if (!reason) return; setBusyId(order.id); try { await grantServiceOrderOverride(order.id, reason); await releaseServiceOrder(order.id, user?.id, `Override: ${reason}`); playWorkflowSound('success'); toast({ title: 'Override approved', description: `${order.service_name} has been released.` }); await load(); } catch (error) { playWorkflowSound('critical'); toast({ title: 'Override failed', description: error instanceof Error ? error.message : 'Unable to grant override.', variant: 'destructive' }); } finally { setBusyId(null); } };
  const reject = async (order: AccountsOrder) => { setBusyId(order.id); try { await cancelServiceOrder(order.id, 'Cancelled by Accounts'); playWorkflowSound('success'); toast({ title: 'Order cancelled' }); await load(); } catch (error) { playWorkflowSound('critical'); toast({ title: 'Cancellation failed', description: error instanceof Error ? error.message : 'Unable to cancel order.', variant: 'destructive' }); } finally { setBusyId(null); } };
  const activateCoverage = async (order: AccountsOrder) => { setBusyId(order.id); try { const { error } = await supabase.rpc('activate_patient_visit_coverage' as never, { _patient_id: order.patient_id, _source: 'accounts', _appointment_id: null } as never); if (error) throw error; playWorkflowSound('success'); toast({ title: 'Daily coverage activated', description: 'New eligible orders created today will release automatically.' }); } catch (error) { playWorkflowSound('critical'); toast({ title: 'Coverage activation failed', description: error instanceof Error ? error.message : 'Unable to activate coverage.', variant: 'destructive' }); } finally { setBusyId(null); } };
  const changeFlow = async (value: PaymentFlow) => { try { await setPaymentFlow(value); setFlow(value); playWorkflowSound('success'); toast({ title: 'Routing updated' }); } catch (error) { playWorkflowSound('critical'); toast({ title: 'Routing update failed', description: error instanceof Error ? error.message : 'Unable to update routing.', variant: 'destructive' }); } };
  const reconcileDischarge = async (notice: DischargeNotice) => {
    setBusyId(notice.id);
    const { data, error } = await supabase.rpc('reconcile_discharge_billing', { _notification_id: notice.id } as never);
    setBusyId(null);
    if (error) { playWorkflowSound('critical'); toast({ title: 'Reconciliation failed', description: error.message, variant: 'destructive' }); return; }
    const row = data as { notification_id: string; patient_id: string; gross: number; paid: number; outstanding: number; insurance_claimed: number; insurance_paid: number; status: string };
    setReconciliations((current) => ({ ...current, [notice.id]: { notificationId: notice.id, patientId: row.patient_id, gross: Number(row.gross || 0), paid: Number(row.paid || 0), outstanding: Number(row.outstanding || 0), insuranceClaimed: Number(row.insurance_claimed || 0), insurancePaid: Number(row.insurance_paid || 0), status: row.status } }));
    playWorkflowSound(row.status === 'fully_settled' ? 'success' : 'warning');
    toast({ title: 'Discharge account reconciled', description: `${money(Number(row.gross || 0))} final bill · ${money(Number(row.outstanding || 0))} outstanding.` });
    await load();
  };
  const openBilling = (patientId: string | null) => { window.location.assign(patientId ? `/billing?patient=${encodeURIComponent(patientId)}` : '/billing'); };

  const acknowledgeDischarge = async (id: string) => { const { error } = await supabase.rpc('mark_notification_read', { _notification_id: id }); if (error) { playWorkflowSound('critical'); toast({ title: 'Could not acknowledge handoff', description: error.message, variant: 'destructive' }); return; } playWorkflowSound('success'); await load(); };

  const counterCards = [
    { label: 'Awaiting approval', value: counts.pending, icon: Clock3, tone: 'text-warning', surface: 'bg-warning/5', status: 'pending_payment_approval' as ServiceOrderStatus },
    { label: 'Released to departments', value: counts.released, icon: BadgeCheck, tone: 'text-success', surface: 'bg-success/5', status: 'released' as ServiceOrderStatus },
    { label: 'Currently in service', value: counts.inProgress, icon: Activity, tone: 'text-info', surface: 'bg-info/5', status: 'in_progress' as ServiceOrderStatus },
    { label: 'Completed services', value: counts.completed, icon: CheckCircle2, tone: 'text-primary', surface: 'bg-primary/5', status: 'completed' as ServiceOrderStatus },
  ];

  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Banknote className="w-6 h-6 text-primary" /> Accounts Approvals</h1><p className="text-muted-foreground">Release paid services and reconcile discharged inpatient accounts.</p></div><select value={filter} onChange={(e) => setFilter(e.target.value as ServiceOrderStatus)} className="input-medical max-w-xs"><option value="pending_payment_approval">Awaiting payment approval</option><option value="released">Released</option><option value="in_progress">In progress</option><option value="completed">Completed</option><option value="cancelled">Cancelled</option></select></div>
    <section aria-label="Accounts workflow counters" className="grid grid-cols-2 lg:grid-cols-4 gap-3">{counterCards.map(({ label, value, icon: Icon, tone, surface, status }) => <button key={label} type="button" onClick={() => setFilter(status)} className={`card-medical ${surface} p-4 text-left transition-all duration-300 hover:-translate-y-1 hover:shadow-elevated ${value > 0 && status === 'pending_payment_approval' ? 'ring-1 ring-warning/30 animate-pulse' : ''}`}><div className="flex items-start justify-between gap-2"><div><p className="text-xs text-muted-foreground">{label}</p><p className={`text-2xl font-bold ${tone}`}>{value}</p></div><Icon className={`w-5 h-5 ${tone}`} /></div><p className="text-[10px] text-muted-foreground mt-2">Open this worklist →</p></button>)}</section>
    <section className={`card-medical p-5 ${counts.discharged > 0 ? 'ring-1 ring-warning/30 animate-pulse' : ''}`}><div className="flex items-center justify-between gap-3"><div><h2 className="font-semibold flex items-center gap-2"><LogOut className="w-4 h-4 text-warning" /> Discharge reconciliation queue <span className="rounded-full bg-warning/10 px-2 py-0.5 text-warning text-xs">{counts.discharged}</span></h2><p className="text-xs text-muted-foreground">Discharged inpatient episodes awaiting Accounts review of the complete patient bill.</p></div><button type="button" onClick={() => window.location.assign('/billing')} className="btn-secondary">Open Billing</button></div>{dischargeNotices.length > 0 && <div className="mt-4 space-y-2">{dischargeNotices.map((notice) => { const result = reconciliations[notice.id]; return <div key={notice.id} className="rounded-lg border border-warning/20 bg-warning/5 p-3 flex flex-col gap-3"><div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"><div><p className="text-sm">{notice.message}</p><p className="text-[11px] text-muted-foreground">{new Date(notice.created_at).toLocaleString()}</p></div><div className="flex flex-wrap gap-2"><button type="button" disabled={busyId === notice.id} onClick={() => void reconcileDischarge(notice)} className="btn-primary inline-flex items-center gap-1 text-xs disabled:opacity-50"><ReceiptText className="w-3 h-3" />{busyId === notice.id ? 'Reconciling…' : 'Reconcile final bill'}</button><button type="button" onClick={() => openBilling(notice.related_patient_id)} className="btn-secondary text-xs">Open patient billing</button><button type="button" onClick={() => void acknowledgeDischarge(notice.id)} className="btn-ghost text-xs">Acknowledge</button></div></div>{result && <div className="grid grid-cols-2 md:grid-cols-5 gap-2 text-xs"><div><span className="text-muted-foreground">Final bill</span><p className="font-semibold">{money(result.gross)}</p></div><div><span className="text-muted-foreground">Paid</span><p className="font-semibold">{money(result.paid)}</p></div><div><span className="text-muted-foreground">Outstanding</span><p className="font-semibold">{money(result.outstanding)}</p></div><div><span className="text-muted-foreground">Insurance claimed</span><p className="font-semibold">{money(result.insuranceClaimed)}</p></div><div><span className="text-muted-foreground">State</span><p className="font-semibold capitalize">{result.status.replaceAll('_', ' ')}</p></div></div>}</div>; })}</div>}</section>
    {isAdmin && <div className="card-medical p-5"><div className="flex items-center gap-2 mb-2 font-semibold"><Settings2 className="w-4 h-4" /> Patient routing style</div><div className="flex flex-wrap gap-3 text-sm"><label className="flex items-center gap-2"><input type="radio" checked={flow === 'strict'} onChange={() => void changeFlow('strict')} /> Accounts stop before every step</label><label className="flex items-center gap-2"><input type="radio" checked={flow === 'streamlined'} onChange={() => void changeFlow('streamlined')} /> Streamlined routing between clinical steps</label></div></div>}
    <div className="space-y-3">{orders.length === 0 && <p className="text-sm text-muted-foreground">Nothing in this list.</p>}{orders.map((order) => { const patient = order.patients; const busy = busyId === order.id; return <div key={order.id} className="card-medical p-5 flex flex-col gap-3 md:flex-row md:items-center md:justify-between"><div><p className="font-semibold">{order.service_name}</p><p className="text-sm text-muted-foreground">{patient?.first_name} {patient?.last_name} · {patient?.patient_code} · {order.department}</p>{patient?.insurance_provider && <p className="text-xs text-primary mt-1">Insurance: {patient.insurance_provider} · {patient.insurance_number ?? 'no number on file'}</p>}<p className="text-xs text-muted-foreground mt-1">{STATUS_LABEL[order.status]}</p></div><div className="flex flex-wrap items-center gap-3"><span className="text-lg font-semibold">GHS {Number(order.amount).toFixed(2)}</span>{order.status === 'pending_payment_approval' && <>{patient?.insurance_provider && <button disabled={busy} onClick={() => void activateCoverage(order)} className="btn-secondary inline-flex items-center gap-2 disabled:opacity-50"><ShieldCheck className="w-4 h-4" /> Activate today's coverage</button>}<button disabled={busy} onClick={() => void approve(order)} className="btn-primary inline-flex items-center gap-2 disabled:opacity-50"><BadgeCheck className="w-4 h-4" /> Approve & release</button><button disabled={busy} onClick={() => void override(order)} className="btn-secondary inline-flex items-center gap-2 disabled:opacity-50"><ShieldCheck className="w-4 h-4" /> Override</button><button disabled={busy} onClick={() => void reject(order)} className="btn-secondary inline-flex items-center gap-2 disabled:opacity-50"><XCircle className="w-4 h-4" /> Cancel</button></>}</div></div>; })}</div>
  </div>;
}