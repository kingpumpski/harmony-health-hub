// @ts-nocheck -- schema types lag behind live database functions; runtime unaffected
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Calendar, CheckCircle2, Clock3, Plus, RefreshCw, ShieldAlert, Utensils } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';

type MenuItem = { name: string; description?: string; dietary_tags: string[]; allergens: string[]; ingredients?: string };
type Menu = { id: string; service_date: string; meal_period: string; available_from: string | null; available_until: string | null; status: string; notes: string | null; items: MenuItem[] };
type ActiveOrder = { order_id: string; patient_id: string; patient_code: string | null; patient_name: string; meal_type: string; scheduled_for: string; order_status: string; plan_type: string | null; dietary_restrictions: string | null; underlying_conditions: string | null; current_diagnoses: Array<{ diagnosis: string; icd_code?: string | null; principal?: boolean; provisional?: boolean }>; };

const periods = ['breakfast','morning_snack','lunch','afternoon_snack','dinner','night_snack'];
const periodLabel = (value: string) => value.replaceAll('_',' ').replace(/\b\w/g, m => m.toUpperCase());
const today = () => new Date().toISOString().slice(0,10);

export default function CanteenMeals() {
  const { user } = useAuth();
  const role = String(user?.role ?? '');
  const canManage = role === 'canteen' || role === 'admin';
  const [date, setDate] = useState(today());
  const [menus, setMenus] = useState<Menu[]>([]);
  const [orders, setOrders] = useState<ActiveOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [mealPeriod, setMealPeriod] = useState('lunch');
  const [fromTime, setFromTime] = useState('12:00');
  const [untilTime, setUntilTime] = useState('14:00');
  const [notes, setNotes] = useState('');
  const [items, setItems] = useState<MenuItem[]>([{ name: '', description: '', dietary_tags: [], allergens: [], ingredients: '' }]);
  const [planPatientId, setPlanPatientId] = useState('');
  const [planType, setPlanType] = useState('Regular');
  const [planRestrictions, setPlanRestrictions] = useState('');

  const loadMenus = useCallback(async () => {
    if (!canManage) {
      const { data, error } = await (supabase as any).rpc('get_patient_portal_meal_menus', { _service_date: date }, { get: true });
      if (error) { toast({ title: 'Meal menu unavailable', description: error.message, variant: 'destructive' }); setMenus([]); return; }
      setMenus((data ?? []) as Menu[]);
      return;
    }
    const { data: menuRows, error } = await (supabase as any).from('meal_menus').select('id,service_date,meal_period,available_from,available_until,status,notes').eq('service_date', date).order('meal_period');
    if (error) { toast({ title: 'Menu unavailable', description: error.message, variant: 'destructive' }); return; }
    const ids = (menuRows ?? []).map((m: any) => m.id);
    let itemRows: any[] = [];
    if (ids.length) {
      const { data, error: itemError } = await (supabase as any).from('meal_menu_items').select('menu_id,name,description,dietary_tags,allergens,ingredients,sort_order,active').in('menu_id', ids).order('sort_order');
      if (itemError) { toast({ title: 'Menu items unavailable', description: itemError.message, variant: 'destructive' }); return; }
      itemRows = data ?? [];
    }
    setMenus((menuRows ?? []).map((m: any) => ({ ...m, items: itemRows.filter(i => i.menu_id === m.id) })));
  }, [date, canManage]);

  const loadOrders = useCallback(async () => {
    if (!canManage) return;
    const { data, error } = await (supabase as any).rpc('get_canteen_active_patient_orders');
    if (error) { toast({ title: 'Active patient orders unavailable', description: error.message, variant: 'destructive' }); return; }
    setOrders((data ?? []) as ActiveOrder[]);
  }, [canManage]);

  const load = useCallback(async () => { setLoading(true); await Promise.all([loadMenus(), loadOrders()]); setLoading(false); }, [loadMenus, loadOrders]);
  useEffect(() => { void load(); }, [load]);

  useEffect(() => {
    if (!canManage) return;
    let channel: ReturnType<typeof supabase.channel> | null = null;
    let active = true;
    void (async () => {
      await supabase.realtime.setAuth();
      if (!active) return;
      channel = supabase.channel('canteen:operations', { config: { private: true } })
        .on('broadcast', { event: 'canteen_context_changed' }, () => { void loadOrders(); })
        .subscribe((status, error) => { if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') console.error('Canteen realtime channel error', error); });
    })();
    return () => { active = false; if (channel) void supabase.removeChannel(channel); };
  }, [canManage, loadOrders]);

  useEffect(() => {
    const channel = supabase.channel('meal-menu-publication')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'meal_menus' }, () => { void loadMenus(); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'meal_menu_items' }, () => { void loadMenus(); })
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [loadMenus]);

  const editMenu = (menu: Menu) => {
    setMealPeriod(menu.meal_period); setNotes(menu.notes ?? '');
    setFromTime(menu.available_from ? new Date(menu.available_from).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false }) : '');
    setUntilTime(menu.available_until ? new Date(menu.available_until).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false }) : '');
    setItems(menu.items.length ? menu.items.map(({ name, description, dietary_tags, allergens, ingredients }) => ({ name, description: description ?? '', dietary_tags: dietary_tags ?? [], allergens: allergens ?? [], ingredients: ingredients ?? '' })) : [{ name: '', description: '', dietary_tags: [], allergens: [], ingredients: '' }]);
  };

  const saveMenu = async (publish: boolean) => {
    const validItems = items.filter(i => i.name.trim());
    if (!validItems.length) { toast({ title: 'Add at least one meal option', variant: 'destructive' }); return; }
    setSaving(true);
    const from = fromTime ? new Date(`${date}T${fromTime}:00`).toISOString() : null;
    const until = untilTime ? new Date(`${date}T${untilTime}:00`).toISOString() : null;
    const { error } = await (supabase as any).rpc('save_canteen_menu', { _service_date: date, _meal_period: mealPeriod, _available_from: from, _available_until: until, _items: validItems, _notes: notes || null, _publish: publish });
    setSaving(false);
    if (error) { toast({ title: 'Menu could not be saved', description: error.message, variant: 'destructive' }); return; }
    toast({ title: publish ? 'Menu published' : 'Menu saved as draft' }); await loadMenus();
  };

  const createPlan = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!planPatientId) { toast({ title: 'Select an active patient order first', variant: 'destructive' }); return; }
    const { error } = await supabase.rpc('create_meal_plan_workflow', { _patient_id: planPatientId, _plan_type: planType, _restrictions: planRestrictions || null });
    if (error) { toast({ title: 'Dietary plan could not be created', description: error.message, variant: 'destructive' }); return; }
    toast({ title: 'Dietary plan created' });
    setPlanPatientId(''); setPlanRestrictions('');
    await loadOrders();
  };

  const markDelivered = async (id: string) => {
    const { error } = await supabase.rpc('mark_meal_order_delivered', { _order_id: id });
    if (error) { toast({ title: 'Delivery update failed', description: error.message, variant: 'destructive' }); return; }
    await loadOrders();
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <header className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div><p className="text-xs font-semibold uppercase tracking-wider text-primary">{canManage ? 'Canteen operations' : 'Patient meal information'}</p><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Utensils className="h-6 w-6 text-primary" /> Meals & Dietary Services</h1><p className="mt-1 text-sm text-muted-foreground">{canManage ? 'Manage time-specific menus and serve each active patient according to documented dietary context.' : 'View the published meal options available by day and meal period.'}</p></div>
        <button type="button" onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="h-4 w-4" />{loading ? 'Refreshing…' : 'Refresh'}</button>
      </header>

      <section className="card-medical p-5">
        <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between"><label className="text-sm font-medium">Service date<input type="date" value={date} onChange={e => setDate(e.target.value)} className="input-medical mt-1" /></label><div className="text-xs text-muted-foreground">Published menus are visible to authenticated users without exposing patient clinical information.</div></div>
        <div className="mt-4 grid gap-3 md:grid-cols-2 lg:grid-cols-3">
          {menus.map(menu => <button type="button" key={menu.id} onClick={() => canManage && editMenu(menu)} className="rounded-xl border border-border p-4 text-left hover:bg-muted/30"><div className="flex items-center justify-between gap-2"><span className="font-semibold">{periodLabel(menu.meal_period)}</span><span className="rounded-full border px-2 py-0.5 text-[10px] capitalize">{menu.status}</span></div><p className="mt-1 text-sm text-muted-foreground">{menu.items.length} option{menu.items.length === 1 ? '' : 's'}{menu.available_from ? ` · ${new Date(menu.available_from).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : ''}</p><div className="mt-3 space-y-1">{menu.items.map(item => <div key={item.name} className="text-sm"><span className="font-medium">{item.name}</span>{item.dietary_tags?.length ? <span className="ml-2 text-xs text-muted-foreground">{item.dietary_tags.join(' · ')}</span> : null}</div>)}</div></button>)}
          {!menus.length && <p className="text-sm text-muted-foreground">No menu has been published for this service date.</p>}
        </div>
      </section>

      {canManage && <>
        <section className="card-medical p-5">
          <div className="flex items-center gap-2"><Calendar className="h-5 w-5 text-primary" /><div><h2 className="font-semibold">Create or update a menu</h2><p className="text-xs text-muted-foreground">Create a separate menu for each date and service period. Publishing makes it visible to patients and other authenticated users.</p></div></div>
          <div className="mt-4 grid gap-3 md:grid-cols-2 lg:grid-cols-4"><select value={mealPeriod} onChange={e => setMealPeriod(e.target.value)} className="input-medical">{periods.map(p => <option key={p} value={p}>{periodLabel(p)}</option>)}</select><input type="time" value={fromTime} onChange={e => setFromTime(e.target.value)} className="input-medical" aria-label="Available from" /><input type="time" value={untilTime} onChange={e => setUntilTime(e.target.value)} className="input-medical" aria-label="Available until" /><input value={notes} onChange={e => setNotes(e.target.value)} placeholder="Menu notes" className="input-medical" /></div>
          <div className="mt-4 space-y-3">{items.map((item, index) => <div key={index} className="grid gap-2 rounded-xl border border-border p-3 md:grid-cols-2 lg:grid-cols-5"><input value={item.name} onChange={e => setItems(v => v.map((x,i) => i === index ? { ...x, name: e.target.value } : x))} placeholder="Meal option" className="input-medical" /><input value={item.description} onChange={e => setItems(v => v.map((x,i) => i === index ? { ...x, description: e.target.value } : x))} placeholder="Description" className="input-medical" /><input value={item.dietary_tags.join(', ')} onChange={e => setItems(v => v.map((x,i) => i === index ? { ...x, dietary_tags: e.target.value.split(',').map(s => s.trim()).filter(Boolean) } : x))} placeholder="Dietary tags" className="input-medical" /><input value={item.allergens.join(', ')} onChange={e => setItems(v => v.map((x,i) => i === index ? { ...x, allergens: e.target.value.split(',').map(s => s.trim()).filter(Boolean) } : x))} placeholder="Allergens" className="input-medical" /><div className="flex gap-2"><input value={item.ingredients} onChange={e => setItems(v => v.map((x,i) => i === index ? { ...x, ingredients: e.target.value } : x))} placeholder="Ingredients" className="input-medical min-w-0 flex-1" /><button type="button" className="btn-ghost" onClick={() => setItems(v => v.length > 1 ? v.filter((_,i) => i !== index) : v)} aria-label="Remove menu item">×</button></div></div>)}
          <button type="button" className="btn-ghost inline-flex items-center gap-2" onClick={() => setItems(v => [...v, { name: '', description: '', dietary_tags: [], allergens: [], ingredients: '' }])}><Plus className="h-4 w-4" /> Add meal option</button></div>
          <div className="mt-4 flex flex-wrap gap-2"><button type="button" disabled={saving} onClick={() => void saveMenu(false)} className="btn-secondary">{saving ? 'Saving…' : 'Save draft'}</button><button type="button" disabled={saving} onClick={() => void saveMenu(true)} className="btn-primary">{saving ? 'Publishing…' : 'Publish menu'}</button></div>
        </section>

        <section className="card-medical p-5">
          <div className="flex items-center gap-2"><ShieldAlert className="h-5 w-5 text-primary" /><div><h2 className="font-semibold">Patient dietary plan</h2><p className="text-xs text-muted-foreground">Create a meal-service plan for an active ordered patient. Clinical conditions remain read-only context.</p></div></div>
          <form onSubmit={createPlan} className="mt-4 grid gap-3 md:grid-cols-3">
            <select value={planPatientId} onChange={e => setPlanPatientId(e.target.value)} className="input-medical"><option value="">Select active patient…</option>{orders.map(order => <option key={order.patient_id} value={order.patient_id}>{order.patient_name}{order.patient_code ? ` · ${order.patient_code}` : ''}</option>)}</select>
            <select value={planType} onChange={e => setPlanType(e.target.value)} className="input-medical"><option>Regular</option><option>Diabetic</option><option>Low-sodium</option><option>Soft / post-op</option><option>Liquid</option><option>High-protein</option></select>
            <div className="flex gap-2"><input value={planRestrictions} onChange={e => setPlanRestrictions(e.target.value)} placeholder="Documented dietary restrictions" className="input-medical min-w-0 flex-1" /><button className="btn-primary">Save plan</button></div>
          </form>
        </section>

        <section className="card-medical p-5">
          <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between"><div><h2 className="font-semibold flex items-center gap-2"><ShieldAlert className="h-5 w-5 text-primary" /> Active patient meal orders</h2><p className="text-xs text-muted-foreground">Live operational context only: underlying documented conditions, current active diagnoses and dietary plan restrictions. No clinical notes, medications or unrelated chart data are exposed to the canteen.</p></div><span className="rounded-full border px-2.5 py-1 text-xs">{orders.length} active</span></div>
          <div className="mt-4 space-y-3">{orders.map(order => <article key={order.order_id} className="rounded-xl border border-border p-4"><div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between"><div><div className="flex flex-wrap items-center gap-2"><h3 className="font-semibold">{order.patient_name}</h3>{order.patient_code ? <span className="text-xs text-muted-foreground">{order.patient_code}</span> : null}<span className="rounded-full border px-2 py-0.5 text-[10px] capitalize">{order.order_status}</span></div><p className="mt-1 text-sm"><Clock3 className="mr-1 inline h-3.5 w-3.5" />{periodLabel(order.meal_type)} · {new Date(order.scheduled_for).toLocaleString()}</p></div>{order.order_status !== 'delivered' && <button type="button" onClick={() => void markDelivered(order.order_id)} className="btn-ghost inline-flex items-center gap-2"><CheckCircle2 className="h-4 w-4" /> Mark delivered</button>}</div>
            <div className="mt-3 grid gap-3 md:grid-cols-3"><div className="rounded-lg bg-muted/30 p-3"><p className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">Underlying conditions</p><p className="mt-1 text-sm">{order.underlying_conditions || 'None documented'}</p></div><div className="rounded-lg bg-muted/30 p-3"><p className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">Current diagnoses</p>{order.current_diagnoses?.length ? <ul className="mt-1 space-y-1 text-sm">{order.current_diagnoses.map((d,i) => <li key={i}>{d.diagnosis}{d.icd_code ? <span className="ml-1 text-xs text-muted-foreground">({d.icd_code})</span> : null}{d.provisional ? <span className="ml-1 text-[10px] text-muted-foreground">provisional</span> : null}</li>)}</ul> : <p className="mt-1 text-sm">No active diagnosis documented</p>}</div><div className="rounded-lg bg-muted/30 p-3"><p className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">Dietary plan</p><p className="mt-1 text-sm">{order.plan_type || 'No plan recorded'}</p>{order.dietary_restrictions ? <p className="mt-1 text-xs text-muted-foreground">{order.dietary_restrictions}</p> : null}</div></div>
            <p className="mt-3 text-[10px] text-muted-foreground">Clinical context is displayed to support meal-service safety; it is not a diagnosis or dietary prescription. Follow the documented dietary plan and clinical instructions.</p>
          </article>)}{!orders.length && <p className="py-6 text-center text-sm text-muted-foreground">No active meal orders in the current operational window.</p>}</div>
        </section>
      </>}
    </div>
  );
}