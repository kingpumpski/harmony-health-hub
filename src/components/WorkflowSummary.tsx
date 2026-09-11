import { useEffect, useState } from 'react';
import { Activity, CalendarDays, CreditCard, Users } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface Counts { pending: number; activeServices: number; appointments: number; activeAdmissions: number }

export default function WorkflowSummary() {
  const [counts, setCounts] = useState<Counts>({ pending: 0, activeServices: 0, appointments: 0, activeAdmissions: 0 });

  useEffect(() => {
    let mounted = true;
    const load = async () => {
      const start = new Date(); start.setHours(0, 0, 0, 0);
      const end = new Date(); end.setHours(23, 59, 59, 999);
      const [{ count: pending }, { count: activeServices }, { count: appointments }, { count: activeAdmissions }] = await Promise.all([
        supabase.from('service_orders').select('id', { count: 'exact', head: true }).eq('status', 'pending_payment_approval'),
        supabase.from('service_orders').select('id', { count: 'exact', head: true }).in('status', ['released', 'in_progress']),
        supabase.from('appointments').select('id', { count: 'exact', head: true }).gte('scheduled_at', start.toISOString()).lte('scheduled_at', end.toISOString()),
        supabase.from('admissions').select('id', { count: 'exact', head: true }).is('discharged_at', null),
      ]);
      if (mounted) setCounts({ pending: pending ?? 0, activeServices: activeServices ?? 0, appointments: appointments ?? 0, activeAdmissions: activeAdmissions ?? 0 });
    };
    void load();
    const channel = supabase.channel('workflow-summary').on('postgres_changes', { event: '*', schema: 'public', table: 'service_orders' }, () => void load()).subscribe();
    return () => { mounted = false; void supabase.removeChannel(channel); };
  }, []);

  const cards = [
    { label: 'Payment approvals', value: counts.pending, icon: CreditCard, tone: 'text-warning' },
    { label: 'Active services', value: counts.activeServices, icon: Activity, tone: 'text-primary' },
    { label: "Today's appointments", value: counts.appointments, icon: CalendarDays, tone: 'text-success' },
    { label: 'Active admissions', value: counts.activeAdmissions, icon: Users, tone: 'text-critical' },
  ];

  return <div className="grid grid-cols-2 xl:grid-cols-4 gap-3 mb-6">{cards.map(({ label, value, icon: Icon, tone }) => <div key={label} className="card-medical p-4"><div className="flex items-center justify-between gap-3"><div><p className="text-xs text-muted-foreground">{label}</p><p className="text-2xl font-bold mt-1">{value}</p></div><Icon className={`w-5 h-5 ${tone}`} /></div></div>)}</div>;
}
