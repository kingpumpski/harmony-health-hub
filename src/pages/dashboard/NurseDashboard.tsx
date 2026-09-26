import { useCallback, useEffect, useMemo, useState } from 'react';
import { Activity, AlertTriangle, BedDouble, BellRing, ClipboardList, FileText, HeartPulse, Pill, RefreshCw, Syringe, Users } from 'lucide-react';
import { Link } from 'react-router-dom';
import StatCard from '@/components/ui/StatCard';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

type Patient = { id: string; patient_code: string; first_name: string; last_name: string };
type DashboardRow = Record<string, any>;

const statusTone = (status: string) => status === 'critical' ? 'bg-critical/5 border-l-2 border-l-critical' : status === 'attention' ? 'bg-warning/5 border-l-2 border-l-warning' : '';

export default function NurseDashboard() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<Patient[]>([]);
  const [admissions, setAdmissions] = useState<DashboardRow[]>([]);
  const [medications, setMedications] = useState<DashboardRow[]>([]);
  const [handovers, setHandovers] = useState<DashboardRow[]>([]);
  const [triage, setTriage] = useState<DashboardRow[]>([]);
  const [queue, setQueue] = useState<DashboardRow[]>([]);
  const [workflowNotifications, setWorkflowNotifications] = useState<DashboardRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<'all' | 'critical' | 'attention'>('all');

  const load = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    const { data, error } = await supabase.functions.invoke('ai-clinical-assist', { body: { mode: 'nurse_dashboard' } });
    if (error || data?.error) {
      toast.error('Nursing dashboard refresh: ' + (data?.error ?? error?.message ?? 'Workspace unavailable'));
    } else {
      setPatients((data?.patients ?? []) as Patient[]);
      setAdmissions((data?.admissions ?? []) as DashboardRow[]);
      setMedications((data?.medications ?? []) as DashboardRow[]);
      setHandovers((data?.handovers ?? []) as DashboardRow[]);
      setTriage((data?.triage ?? []) as DashboardRow[]);
      setQueue((data?.queue ?? []) as DashboardRow[]);
      const { data: notifications } = await (supabase as any).rpc('get_workflow_notifications', { _limit: 100 });
      setWorkflowNotifications((Array.isArray(notifications) ? notifications : []) as DashboardRow[]);
    }
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    const channel = supabase.channel(`nurse-dashboard-${user?.id ?? 'station'}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'medication_administrations' }, () => { playWorkflowSound('info'); void load(true); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'department_queues' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'nursing_shift_handovers' }, () => void load(true))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'triage_assessments' }, () => { playWorkflowSound('critical'); void load(true); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'admissions' }, () => { playWorkflowSound('info'); void load(true); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, () => { playWorkflowSound('info'); void load(true); })
      .subscribe();
    const timer = window.setInterval(() => void load(true), 60000);
    return () => { void supabase.removeChannel(channel); window.clearInterval(timer); };
  }, [load, user?.id]);

  const patientName = (id?: string) => {
    const p = patients.find(x => x.id === id);
    return p ? `${p.first_name} ${p.last_name}` : 'Patient';
  };
  const activeAdmissions = useMemo(() => admissions.filter(a => !a.discharged_at && a.status !== 'discharged'), [admissions]);
  const dueMeds = useMemo(() => medications.filter(m => m.status === 'scheduled' && !m.locked_at), [medications]);
  const overdueMeds = useMemo(() => dueMeds.filter(m => m.scheduled_at && new Date(m.scheduled_at).getTime() < Date.now()), [dueMeds]);
  const criticalPatients = useMemo(() => triage.filter(t => ['critical', 'urgent'].includes(String(t.priority ?? t.status ?? '').toLowerCase())).slice(0, 12), [triage]);
  const pendingHandovers = useMemo(() => handovers.filter(h => !h.acknowledged_at), [handovers]);
  const inpatientRows = useMemo(() => activeAdmissions.slice(0, 30).map(a => ({ ...a, status: criticalPatients.some(t => t.patient_id === a.patient_id) ? 'critical' : 'stable' })), [activeAdmissions, criticalPatients]);
  const unreadAdmissionAlerts = useMemo(() => workflowNotifications.filter(n => !n.is_read && /new inpatient admission/i.test(String(n.title ?? ''))), [workflowNotifications]);

  const refresh = () => { void load(); };

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-heading font-bold">Nursing Station</h1>
          <p className="text-muted-foreground">Live inpatient care, medication administration, handover and escalation workspace.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link to="/nursing-handover" className="btn-secondary"><FileText className="w-4 h-4" /> Nursing Handover</Link><Link to="/nursing-notes" className="btn-secondary"><FileText className="w-4 h-4" /> Nursing Notes</Link>
          <Link to="/vitals" className="btn-primary"><HeartPulse className="w-4 h-4" /> Record Vitals</Link>
          <button onClick={refresh} className="btn-ghost" aria-label="Refresh nursing dashboard"><RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} /></button>
        </div>
      </div>

      {unreadAdmissionAlerts.length > 0 && <div className="rounded-xl border border-info/30 bg-info/5 p-4 flex flex-wrap items-center justify-between gap-3 animate-pulse">
        <div className="flex items-center gap-3"><BellRing className="w-5 h-5 text-info" /><div><p className="font-semibold text-info">New inpatient admission</p><p className="text-sm text-muted-foreground">{unreadAdmissionAlerts.length} admission notification(s) require acknowledgement in the nursing workflow.</p></div></div>
        <Link to="/notifications" className="btn-secondary">Review admission alerts</Link>
      </div>}

      {criticalPatients.length > 0 && <div className="rounded-xl border border-critical/30 bg-critical/5 p-4 flex flex-wrap items-center justify-between gap-3 animate-pulse">
        <div className="flex items-center gap-3"><AlertTriangle className="w-5 h-5 text-critical" /><div><p className="font-semibold text-critical">Clinical attention required</p><p className="text-sm text-muted-foreground">{criticalPatients.length} recent critical/urgent triage record(s) require nursing review.</p></div></div>
        <Link to="/vitals" className="btn-secondary">Open vitals</Link>
      </div>}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
        <StatCard title="Active Inpatients" value={activeAdmissions.length} change="Open admissions" changeType="neutral" icon={BedDouble} iconColor="text-primary" />
        <StatCard title="Medications Due" value={dueMeds.length} change={`${overdueMeds.length} overdue`} changeType={overdueMeds.length ? 'negative' : 'neutral'} icon={Pill} iconColor="text-warning" />
        <StatCard title="Vitals / Escalations" value={criticalPatients.length} change="Critical or urgent" changeType={criticalPatients.length ? 'negative' : 'neutral'} icon={HeartPulse} iconColor="text-critical" />
        <StatCard title="Unacknowledged Handovers" value={pendingHandovers.length} change="Continuity actions" changeType="neutral" icon={ClipboardList} iconColor="text-info" />
        <StatCard title="Nursing Queue" value={queue.length} change="Waiting / claimed" changeType="neutral" icon={Users} iconColor="text-primary" />
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <Link to="/nursing-handover" className="card-medical p-4 bg-info/5 hover:bg-info/10 transition-all hover:-translate-y-0.5"><BellRing className="w-4 h-4 mb-2" /><p className="text-xs text-muted-foreground">Handover</p><p className="text-2xl font-bold tabular-nums">{pendingHandovers.length}</p></Link>
        <Link to="/medications" className="card-medical p-4 bg-warning/5 hover:bg-warning/10 transition-all hover:-translate-y-0.5"><Syringe className="w-4 h-4 mb-2" /><p className="text-xs text-muted-foreground">Medication due</p><p className="text-2xl font-bold tabular-nums">{dueMeds.length}</p></Link>
        <Link to="/vitals" className="card-medical p-4 bg-critical/5 hover:bg-critical/10 transition-all hover:-translate-y-0.5"><Activity className="w-4 h-4 mb-2" /><p className="text-xs text-muted-foreground">Critical review</p><p className="text-2xl font-bold tabular-nums">{criticalPatients.length}</p></Link>
        <Link to="/ward-bed-board" className="card-medical p-4 bg-primary/5 hover:bg-primary/10 transition-all hover:-translate-y-0.5"><BedDouble className="w-4 h-4 mb-2" /><p className="text-xs text-muted-foreground">Ward / beds</p><p className="text-sm font-semibold mt-1">Open bed board →</p></Link>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <section className="lg:col-span-2 card-medical">
          <div className="p-5 border-b border-border flex flex-wrap items-center justify-between gap-3">
            <div><h2 className="font-semibold">Current Inpatients</h2><p className="text-xs text-muted-foreground">Live admissions replace the former static demonstration list.</p></div>
            <div className="flex gap-2">{(['all', 'critical', 'attention'] as const).map(f => <button key={f} onClick={() => setFilter(f)} className={cn('px-3 py-1.5 rounded-lg text-sm font-medium capitalize', filter === f ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground')}>{f}</button>)}</div>
          </div>
          <div className="divide-y divide-border">
            {inpatientRows.filter(p => filter === 'all' || p.status === filter).map((patient, index) => (
              <div key={patient.id ?? index} className={cn('p-4 transition-colors hover:bg-muted/30', statusTone(patient.status))}>
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div className="flex items-center gap-3"><div className="text-center px-3 py-2 bg-muted rounded-lg"><p className="text-xs text-muted-foreground">Bed</p><p className="font-bold text-sm">{patient.bed_number ?? patient.bed ?? '—'}</p></div><div><p className="font-medium">{patientName(patient.patient_id)}</p><p className="text-xs text-muted-foreground">{patient.patient_id ?? 'Patient record'} · {patient.ward ?? patient.ward_name ?? 'Ward'}</p>{patient.status === 'critical' && <span className="badge-critical pulse-critical inline-flex mt-1"><AlertTriangle className="w-3 h-3 mr-1" />Clinical review</span>}</div></div>
                  <div className="flex gap-2"><Link to="/vitals" className="btn-secondary text-sm py-1.5"><HeartPulse className="w-4 h-4" /> Vitals</Link><Link to="/medications" className="btn-ghost text-sm py-1.5"><Syringe className="w-4 h-4" /> Meds</Link></div>
                </div>
              </div>
            ))}
            {!inpatientRows.length && <div className="p-8 text-center text-sm text-muted-foreground">No active inpatients are currently available.</div>}
          </div>
        </section>

        <section className="card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between"><div><h2 className="font-semibold">Medication Schedule</h2><p className="text-xs text-muted-foreground">Live MAR slots</p></div><Link to="/medications" className="text-sm text-primary">Open MAR</Link></div>
          <div className="divide-y divide-border max-h-[28rem] overflow-y-auto">
            {dueMeds.slice(0, 20).map((med, index) => <div key={med.id ?? index} className={cn('p-4', overdueMeds.some(x => x.id === med.id) && 'bg-critical/5')}><div className="flex items-start justify-between gap-2"><div><p className="font-medium text-sm">{med.medication_name}</p><p className="text-xs text-muted-foreground">{patientName(med.patient_id)} · {med.dose ?? 'dose not recorded'}</p></div><span className={cn('badge-status', overdueMeds.some(x => x.id === med.id) ? 'badge-critical pulse-critical' : 'badge-warning')}>{med.scheduled_at ? new Date(med.scheduled_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : 'Due'}</span></div></div>)}
            {!dueMeds.length && <div className="p-8 text-center text-sm text-muted-foreground">No medication administrations are currently due.</div>}
          </div>
        </section>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <section className="card-medical p-5"><div className="flex justify-between items-start mb-3"><div><h2 className="font-semibold">Handover & continuity</h2><p className="text-sm text-muted-foreground">Unacknowledged handovers remain visible until acknowledged.</p></div><Link to="/nursing-handover" className="text-sm text-primary">Open</Link></div><p className="text-3xl font-bold tabular-nums">{pendingHandovers.length}</p><p className="text-xs text-muted-foreground mt-1">pending acknowledgement</p></section>
        <section className="card-medical p-5"><div className="flex justify-between items-start mb-3"><div><h2 className="font-semibold">Nursing service queue</h2><p className="text-sm text-muted-foreground">Patients awaiting or already claimed by nursing.</p></div><Link to="/department-queue" className="text-sm text-primary">Open queue</Link></div><p className="text-3xl font-bold tabular-nums">{queue.length}</p><p className="text-xs text-muted-foreground mt-1">active queue items</p></section>
      </div>
    </div>
  );
}
