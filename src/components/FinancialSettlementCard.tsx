import { useCallback, useEffect, useState } from 'react';
import { AlertCircle, CheckCircle2, CircleDollarSign, FileCheck2, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { playWorkflowSound } from '@/lib/workflowFeedback';

interface ClaimSummary { status: string; }

const statusGroups = {
  open: new Set(['draft', 'submitted', 'acknowledged', 'under_review']),
  attention: new Set(['partially_approved', 'rejected', 'resubmission_required']),
  approved: new Set(['approved']),
  paid: new Set(['paid']),
};

export default function FinancialSettlementCard() {
  const { user } = useAuth();
  const [claims, setClaims] = useState<ClaimSummary[]>([]);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    if (!user || !['admin', 'accountant'].includes(String(user.role))) return;
    setLoading(true);
    const { data, error } = await supabase.from('insurance_claims').select('status').neq('status', 'voided').limit(2000);
    setLoading(false);
    if (error) return;
    setClaims((data ?? []) as ClaimSummary[]);
  }, [user]);

  useEffect(() => { void load(); }, [load]);

  useEffect(() => {
    if (!user || !['admin', 'accountant'].includes(String(user.role))) return;
    const channel = supabase.channel(`financial-settlement-${user.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'insurance_claims' }, (payload) => {
        const next = payload.new as ClaimSummary;
        if (next.status === 'paid' || statusGroups.attention.has(next.status)) playWorkflowSound(next.status === 'paid' ? 'success' : 'warning');
        void load();
      })
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [load, user]);

  if (!user || !['admin', 'accountant'].includes(String(user.role))) return null;

  const counts = {
    open: claims.filter((c) => statusGroups.open.has(c.status)).length,
    attention: claims.filter((c) => statusGroups.attention.has(c.status)).length,
    approved: claims.filter((c) => statusGroups.approved.has(c.status)).length,
    paid: claims.filter((c) => statusGroups.paid.has(c.status)).length,
  };

  const cards = [
    { label: 'Claims in process', value: counts.open, icon: RefreshCw, tone: 'text-info', surface: 'bg-info/5', href: '/insurance-claims' },
    { label: 'Settlement attention', value: counts.attention, icon: AlertCircle, tone: 'text-warning', surface: 'bg-warning/5', href: '/insurance-claims' },
    { label: 'Approved awaiting payment', value: counts.approved, icon: FileCheck2, tone: 'text-success', surface: 'bg-success/5', href: '/insurance-claims' },
    { label: 'Insurance payments', value: counts.paid, icon: CircleDollarSign, tone: 'text-primary', surface: 'bg-primary/5', href: '/insurance-claims' },
  ];

  return <section aria-label="Financial settlement" className="card-medical p-5 space-y-4">
    <div className="flex items-center justify-between gap-3">
      <div><h2 className="font-semibold flex items-center gap-2"><CircleDollarSign className="w-4 h-4 text-primary" />Financial settlement</h2><p className="text-xs text-muted-foreground">Live insurance settlement lifecycle for Accounts.</p></div>
      <button type="button" onClick={() => void load()} className="btn-ghost" aria-label="Refresh financial settlement">{loading ? <RefreshCw className="w-4 h-4 animate-spin" /> : <RefreshCw className="w-4 h-4" />}</button>
    </div>
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
      {cards.map(({ label, value, icon: Icon, tone, surface, href }) => <button key={label} type="button" onClick={() => window.location.assign(href)} className={`rounded-xl p-4 text-left ${surface} transition-all duration-300 hover:-translate-y-1 ${value > 0 && label === 'Settlement attention' ? 'ring-1 ring-warning/30 animate-pulse' : ''}`}>
        <div className="flex items-start justify-between gap-2"><div><p className="text-xs text-muted-foreground">{label}</p><p className={`text-2xl font-bold ${tone}`}>{value}</p></div><Icon className={`w-5 h-5 ${tone}`} /></div>
        {label === 'Insurance payments' && value > 0 && <p className="text-[10px] text-success mt-2 inline-flex items-center gap-1"><CheckCircle2 className="w-3 h-3" />Recorded</p>}
      </button>)}
    </div>
  </section>;
}
