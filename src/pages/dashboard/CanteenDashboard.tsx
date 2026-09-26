import { useCallback, useEffect, useState } from 'react';
import { AlertTriangle, ClipboardList, RefreshCw, Utensils } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';

type Card={key:string;label:string;value:number;href:string;description:string};

export default function CanteenDashboard(){
  const [cards,setCards]=useState<Card[]>([]); const [loading,setLoading]=useState(true);
  const load=useCallback(async()=>{setLoading(true);const {data}=await (supabase as any).rpc('get_role_dashboard_summary');setCards((data?.cards??[]) as Card[]);setLoading(false)},[]);
  useEffect(()=>{void load()},[load]);
  const icons:Record<string,typeof Utensils>={meals_due:Utensils,pending:Utensils,plans:ClipboardList,restrictions:AlertTriangle};
  return <div className="space-y-6 animate-fade-in">
    <header className="flex items-center justify-between gap-3"><div><p className="text-xs font-semibold uppercase tracking-wider text-primary">Support Services</p><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Utensils className="h-6 w-6 text-primary"/>Dietary & Kitchen Operations</h1><p className="text-sm text-muted-foreground mt-1">Live meal delivery and dietary-plan workload from the authoritative meal workflows.</p></div><button type="button" onClick={()=>void load()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="h-4 w-4"/>{loading?'Refreshing…':'Refresh'}</button></header>
    <section className="grid grid-cols-2 gap-3 lg:grid-cols-4">{cards.map(c=>{const Icon=icons[c.key]??Utensils;return <Link key={c.key} to={c.href} className="card-medical p-4 hover:-translate-y-0.5 transition-all"><div className="flex justify-between"><p className="text-xs text-muted-foreground">{c.label}</p><Icon className="h-4 w-4 text-primary"/></div><p className="mt-2 text-3xl font-bold tabular-nums">{c.value}</p><p className="mt-1 text-xs text-muted-foreground">{c.description}</p></Link>})}</section>
    <section className="grid gap-3 sm:grid-cols-3"><Link to="/orders" className="card-medical p-5"><p className="font-semibold">Meal orders</p><p className="mt-1 text-sm text-muted-foreground">Review scheduled meals and complete delivery using the protected workflow.</p></Link><Link to="/dietary-plans" className="card-medical p-5"><p className="font-semibold">Dietary plans</p><p className="mt-1 text-sm text-muted-foreground">Review active patient diet plans and restrictions.</p></Link><Link to="/menu" className="card-medical p-5"><p className="font-semibold">Canteen workspace</p><p className="mt-1 text-sm text-muted-foreground">Open the operational meal-management workspace.</p></Link></section>
  </div>;
}