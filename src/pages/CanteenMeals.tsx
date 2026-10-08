// @ts-nocheck -- legacy meal schema is reconciled by server-side patient menu RPCs.
import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Calendar, CheckCircle2, Plus, Utensils } from 'lucide-react';

type MenuItem = { name: string; description?: string; dietary_tags?: string[]; allergens?: string[]; ingredients?: string };
type Menu = { id: string; service_date: string; meal_period: string; available_from: string | null; available_until: string | null; status: string; notes: string | null; items: MenuItem[] };
const today = () => new Date().toISOString().slice(0, 10);
const periodLabel = (value: string) => value.replaceAll('_', ' ').replace(/\b\w/g, (m) => m.toUpperCase());

function PatientMeals() {
  const [date, setDate] = useState(today());
  const [menus, setMenus] = useState<Menu[]>([]);
  const [loading, setLoading] = useState(true);
  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('get_patient_portal_meal_menus', { _service_date: date }, { get: true });
    if (error) {
      setMenus([]);
      if (!error.message.toLowerCase().includes('admitted patients only')) toast({ title: 'Meal menu unavailable', description: error.message, variant: 'destructive' });
    } else setMenus((data ?? []) as Menu[]);
    setLoading(false);
  }, [date]);
  useEffect(() => { void load(); }, [load]);
  return <div className="space-y-6 animate-fade-in">
    <header><p className="text-xs font-semibold uppercase tracking-wider text-primary">Patient meal information</p><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Utensils className="h-6 w-6 text-primary" /> Meals & Dietary Services</h1><p className="mt-1 text-sm text-muted-foreground">Published menus are available only while you are admitted.</p></header>
    <section className="card-medical p-5"><label className="text-sm font-medium">Service date<input aria-label="Service date" type="date" value={date} onChange={e => setDate(e.target.value)} className="input-medical mt-1" /></label><div className="mt-4 grid gap-3 md:grid-cols-2 lg:grid-cols-3">{loading ? <p className="text-sm text-muted-foreground">Loading menu…</p> : menus.map(menu => <article key={menu.id} className="rounded-xl border p-4"><div className="flex items-center justify-between gap-2"><span className="font-semibold">{periodLabel(menu.meal_period)}</span><span className="rounded-full border px-2 py-0.5 text-[10px]">{menu.status}</span></div><p className="mt-1 text-xs text-muted-foreground">{menu.available_from ? new Date(menu.available_from).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'}) : ''}{menu.available_until ? ' — ' + new Date(menu.available_until).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'}) : ''}</p><div className="mt-3 space-y-2">{menu.items.map(item => <div key={item.name} className="rounded-lg bg-muted/40 p-2"><p className="text-sm font-medium">{item.name}</p>{item.description && <p className="text-xs text-muted-foreground">{item.description}</p>}{item.dietary_tags?.length ? <p className="text-xs text-primary">{item.dietary_tags.join(' · ')}</p> : null}{item.allergens?.length ? <p className="text-xs text-destructive">Allergens: {item.allergens.join(', ')}</p> : null}</div>)}</div></article>)}{!loading && !menus.length && <div className="rounded-xl border border-dashed p-6 text-sm text-muted-foreground"><CheckCircle2 className="mr-2 inline h-4 w-4" />No published meal menu is available for this date while admitted.</div>}</div></section>
  </div>;
}

export default function CanteenMeals() {
  const { user } = useAuth();
  if (user?.role === 'patient') return <PatientMeals />;
  const [patients, setPatients] = useState<any[]>([]);
  const [orders, setOrders] = useState<any[]>([]);
  const [plans, setPlans] = useState<any[]>([]);
  const [pid, setPid] = useState(''); const [planType, setPlanType] = useState('Regular'); const [restrictions, setRestrictions] = useState('');
  const load = async () => {
    const [{ data: p }, { data: o }, { data: mp }] = await Promise.all([
      supabase.from('patients').select('id, first_name, last_name').limit(200),
      supabase.from('meal_orders').select('*, patients(first_name,last_name)').order('scheduled_for').limit(50),
      supabase.from('meal_plans').select('*, patients(first_name,last_name)').eq('active', true).limit(50),
    ]);
    setPatients(p ?? []); setOrders(o ?? []); setPlans(mp ?? []);
  };
  useEffect(() => { void load(); }, []);
  const createPlan = async (e: React.FormEvent) => {
    e.preventDefault(); if (!pid) return;
    const { error } = await supabase.from('meal_plans').insert({ patient_id: pid, plan_type: planType, restrictions, created_by: user?.id });
    if (error) return toast({ title: 'Failed to create meal plan', description: error.message, variant: 'destructive' });
    toast({ title: 'Meal plan created' }); setPid(''); setRestrictions(''); void load();
  };
  const markDelivered = async (id: string) => {
    const { error } = await supabase.from('meal_orders').update({ status: 'delivered', delivered_at: new Date().toISOString() }).eq('id', id);
    if (error) toast({ title: 'Delivery update failed', description: error.message, variant: 'destructive' }); else void load();
  };
  return <div className="space-y-6 animate-fade-in">
    <div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Utensils className="w-6 h-6 text-primary" /> Canteen & Meals</h1><p className="text-muted-foreground">Dietary plans and meal delivery scheduling.</p></div>
    <form onSubmit={createPlan} className="card-medical p-5 grid md:grid-cols-4 gap-3"><select required value={pid} onChange={e=>setPid(e.target.value)} className="input-medical"><option value="">Patient…</option>{patients.map(p=><option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}</select><select value={planType} onChange={e=>setPlanType(e.target.value)} className="input-medical"><option>Regular</option><option>Diabetic</option><option>Low-sodium</option><option>Soft / post-op</option><option>Liquid</option><option>High-protein</option></select><input value={restrictions} onChange={e=>setRestrictions(e.target.value)} placeholder="Restrictions" className="input-medical" /><button className="btn-primary"><Plus className="h-4 w-4 mr-1" /> Create plan</button></form>
    <div className="grid lg:grid-cols-2 gap-6"><div className="card-medical p-5"><h2 className="font-semibold mb-3 flex items-center gap-2"><Calendar className="h-4 w-4" />Active plans</h2><div className="space-y-2">{plans.map(p=><div key={p.id} className="rounded-xl border p-3 text-sm"><p className="font-medium">{p.patients?.first_name} {p.patients?.last_name} — {p.plan_type}</p>{p.restrictions && <p className="text-xs text-muted-foreground">Restrictions: {p.restrictions}</p>}</div>)}</div></div><div className="card-medical p-5"><h2 className="font-semibold mb-3">Meal orders</h2><div className="space-y-2">{orders.map(o=><div key={o.id} className="rounded-xl border p-3 text-sm flex justify-between items-center"><div><p className="font-medium">{o.patients?.first_name} {o.patients?.last_name} — {o.meal_type}</p><p className="text-xs text-muted-foreground">{new Date(o.scheduled_for).toLocaleString()}</p></div>{o.status !== 'delivered' && <button type="button" onClick={()=>void markDelivered(o.id)} className="btn-ghost text-xs">Mark delivered</button>}</div>)}{orders.length===0&&<p className="text-sm text-muted-foreground">No orders.</p>}</div></div></div>
  </div>;
}
