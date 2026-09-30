import { useCallback, useEffect, useState } from 'react';
import { Bell, Cloud, FileSearch, RefreshCw, ShieldCheck } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
type Card={key:string;label:string;value:number;href:string;description:string};
export default function ITAdminDashboard(){
  const { user } = useAuth();
  const [cards,setCards]=useState<Card[]>([]); const [loading,setLoading]=useState(true); const [error,setError]=useState<string | null>(null);
  const load=useCallback(async()=>{setLoading(true);setError(null);const {data,error:rpcError}=await (supabase as any).rpc('get_role_dashboard_summary_for_role',{_requested_role:user?.role});if(rpcError){setError(rpcError.message);setCards([])}else setCards((data?.cards??[]) as Card[]);setLoading(false)},[user?.role]);
  useEffect(()=>{void load()},[load]);
  const icons:Record<string,typeof Bell>={notifications:Bell,offline:Cloud,audit:FileSearch};
  return <div className="space-y-5 animate-fade-in">
    <header className="flex flex-wrap items-center justify-between gap-3"><div><p className="text-xs font-semibold uppercase tracking-wider text-primary">Technology Operations</p><h1 className="mt-1 text-2xl font-heading font-bold flex items-center gap-2"><ShieldCheck className="h-6 w-6 text-primary"/>IT Administration</h1><p className="text-sm text-muted-foreground mt-1">Support, synchronization and audit work.</p></div><button type="button" onClick={()=>void load()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="h-4 w-4"/>{loading?'Refreshing…':'Refresh'}</button></header>
    {error&&<div role="alert" className="rounded-xl border border-critical/30 bg-critical/5 p-4 text-sm"><p className="font-medium text-critical">Dashboard data unavailable</p><p className="mt-1 text-muted-foreground">{error}</p><button type="button" onClick={()=>void load()} className="mt-3 btn-secondary">Retry</button></div>}
    <section className="grid grid-cols-1 gap-3 sm:grid-cols-3">{cards.map(c=>{const Icon=icons[c.key]??FileSearch;return <Link key={c.key} to={c.href} className="card-medical p-4 hover:border-primary/40 transition-colors"><div className="flex items-center justify-between"><p className="text-xs text-muted-foreground">{c.label}</p><Icon className="h-4 w-4 text-primary"/></div><p className="mt-2 text-3xl font-bold tabular-nums">{c.value}</p><p className="mt-1 text-xs text-muted-foreground">{c.description}</p></Link>)}</section>
    <section className="grid gap-3 sm:grid-cols-3"><Link to="/admin/logs" className="card-medical p-4"><p className="font-semibold text-sm">System logs</p><p className="mt-1 text-xs text-muted-foreground">Investigate application and audit events.</p></Link><Link to="/admin/offline-sync" className="card-medical p-4"><p className="font-semibold text-sm">Offline synchronization</p><p className="mt-1 text-xs text-muted-foreground">Review queued and failed synchronization.</p></Link><Link to="/notifications" className="card-medical p-4"><p className="font-semibold text-sm">Notifications</p><p className="mt-1 text-xs text-muted-foreground">Review operational alerts.</p></Link></section>
  </div>;
}
