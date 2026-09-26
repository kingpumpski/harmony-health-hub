import { useCallback, useEffect, useState } from 'react';
import { Calendar, CreditCard, BellRing, HeartPulse, RefreshCw } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';

type Card = { key:string; label:string; value:number; href:string; description:string };

export default function PatientDashboard() {
  const [cards,setCards]=useState<Card[]>([]);
  const [loading,setLoading]=useState(true);
  const load=useCallback(async()=>{setLoading(true);const {data,error}=await (supabase as any).rpc('get_role_dashboard_summary');if(!error)setCards((data?.cards??[]) as Card[]);setLoading(false);},[]);
  useEffect(()=>{void load()},[load]);
  const icons:Record<string,typeof Calendar>={appointments:Calendar,unpaid:CreditCard,notifications:BellRing,active_care:HeartPulse};
  return <div className="space-y-6 animate-fade-in">
    <header className="flex items-center justify-between gap-3"><div><p className="text-xs font-semibold uppercase tracking-wider text-primary">My Care</p><h1 className="text-2xl font-heading font-bold">Patient Dashboard</h1><p className="text-sm text-muted-foreground mt-1">Your appointments, care activity and account attention in one place.</p></div><button type="button" onClick={()=>void load()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="h-4 w-4"/>Refresh</button></header>
    <section className="grid grid-cols-2 gap-3 lg:grid-cols-4">{cards.map(c=>{const Icon=icons[c.key]??HeartPulse;return <Link key={c.key} to={c.href} className="card-medical p-4 hover:-translate-y-0.5 transition-all"><div className="flex items-center justify-between"><p className="text-xs text-muted-foreground">{c.label}</p><Icon className="h-4 w-4 text-primary"/></div><p className="mt-2 text-3xl font-bold tabular-nums">{c.value}</p><p className="mt-1 text-xs text-muted-foreground">{c.description}</p></Link>})}</section>
    <div className="grid gap-3 sm:grid-cols-3"><Link to="/patient-portal" className="card-medical p-5"><p className="font-semibold">My health record</p><p className="mt-1 text-sm text-muted-foreground">Review your available care information.</p></Link><Link to="/appointments" className="card-medical p-5"><p className="font-semibold">Appointments</p><p className="mt-1 text-sm text-muted-foreground">View upcoming and previous visits.</p></Link><Link to="/telemedicine" className="card-medical p-5"><p className="font-semibold">Telemedicine</p><p className="mt-1 text-sm text-muted-foreground">Open available virtual-care services.</p></Link></div>
    {loading&&<p className="text-xs text-muted-foreground" role="status">Refreshing your dashboard…</p>}
  </div>;
}