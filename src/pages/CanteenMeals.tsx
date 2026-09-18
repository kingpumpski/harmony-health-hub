import { searchPatientDirectory } from '@/lib/patientDirectory';
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Utensils, Plus } from 'lucide-react';

export default function CanteenMeals() {
  const { user } = useAuth();
  const [patients, setPatients] = useState<any[]>([]);
  const [orders, setOrders] = useState<any[]>([]);
  const [plans, setPlans] = useState<any[]>([]);
  const [pid, setPid] = useState(''); const [planType, setPlanType] = useState('Regular');
  const [restrictions, setRestrictions] = useState('');

  const load = async () => {
    const [{ data: p }, { data: o }, { data: mp }] = await Promise.all([
      searchPatientDirectory('', 200).then(({ data }) => ({ data, error: null })),
      supabase.from('meal_orders').select('*, patients(first_name,last_name)').order('scheduled_for').limit(50),
      supabase.from('meal_plans').select('*, patients(first_name,last_name)').eq('active', true).limit(50),
    ]);
    setPatients(p ?? []); setOrders(o ?? []); setPlans(mp ?? []);
  };
  useEffect(() => { load(); }, []);

  const createPlan = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pid) return;
    const { error } = await supabase.from('meal_plans').insert({
      patient_id: pid, plan_type: planType, restrictions, created_by: user?.id,
    });
    if (error) return toast({ title: 'Failed', variant: 'destructive' });
    toast({ title: 'Meal plan created' });
    setPid(''); setRestrictions('');
    load();
  };

  const markDelivered = async (id: string) => {
    await supabase.from('meal_orders').update({ status: 'delivered', delivered_at: new Date().toISOString() }).eq('id', id);
    load();
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Utensils className="w-6 h-6 text-primary" /> Canteen & Meals</h1>
        <p className="text-muted-foreground">Dietary plans and meal delivery scheduling.</p>
      </div>

      <form onSubmit={createPlan} className="card-medical p-5 grid md:grid-cols-4 gap-3">
        <select value={pid} onChange={e=>setPid(e.target.value)} className="input-medical">
          <option value="">Patient…</option>
          {patients.map(p => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}
        </select>
        <select value={planType} onChange={e=>setPlanType(e.target.value)} className="input-medical">
          <option>Regular</option><option>Diabetic</option><option>Low-sodium</option><option>Soft / post-op</option><option>Liquid</option><option>High-protein</option>
        </select>
        <input value={restrictions} onChange={e=>setRestrictions(e.target.value)} placeholder="Restrictions" className="input-medical" />
        <button className="btn-primary"><Plus className="w-4 h-4 mr-1" /> Create plan</button>
      </form>

      <div className="grid lg:grid-cols-2 gap-6">
        <div className="card-medical p-5">
          <h2 className="font-semibold mb-3">Active plans</h2>
          <div className="space-y-2">
            {plans.map(p => (
              <div key={p.id} className="rounded-xl border border-border p-3 text-sm">
                <p className="font-medium">{p.patients?.first_name} {p.patients?.last_name} — {p.plan_type}</p>
                {p.restrictions && <p className="text-xs text-muted-foreground">Restrictions: {p.restrictions}</p>}
              </div>
            ))}
          </div>
        </div>
        <div className="card-medical p-5">
          <h2 className="font-semibold mb-3">Meal orders</h2>
          <div className="space-y-2">
            {orders.map(o => (
              <div key={o.id} className="rounded-xl border border-border p-3 text-sm flex justify-between items-center">
                <div>
                  <p className="font-medium">{o.patients?.first_name} {o.patients?.last_name} — {o.meal_type}</p>
                  <p className="text-xs text-muted-foreground">{new Date(o.scheduled_for).toLocaleString()}</p>
                </div>
                {o.status !== 'delivered' && <button onClick={() => markDelivered(o.id)} className="btn-ghost text-xs">Mark delivered</button>}
              </div>
            ))}
            {orders.length === 0 && <p className="text-sm text-muted-foreground">No orders.</p>}
          </div>
        </div>
      </div>
    </div>
  );
}
