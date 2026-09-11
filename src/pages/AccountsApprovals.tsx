import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { releaseServiceOrder, cancelServiceOrder, getPaymentFlow, setPaymentFlow, STATUS_LABEL } from '@/lib/workflow';
import { BadgeCheck, Banknote, XCircle, Settings2 } from 'lucide-react';

export default function AccountsApprovals() {
  const { user } = useAuth();
  const [orders, setOrders] = useState<any[]>([]);
  const [flow, setFlow] = useState<'strict' | 'streamlined'>('streamlined');
  const [filter, setFilter] = useState('pending_payment');
  const isAdmin = user?.role === 'admin';

  const load = useCallback(async () => {
    const { data } = await supabase
      .from('service_orders')
      .select('*, patients(first_name,last_name,patient_code,insurance_provider,insurance_number)')
      .eq('status', filter)
      .order('created_at', { ascending: false })
      .limit(100);
    setOrders(data ?? []);
  }, [filter]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => { getPaymentFlow().then(setFlow); }, []);

  const approve = async (order: any) => {
    try {
      await releaseServiceOrder(order.id, user?.id);
      toast({ title: 'Released to department', description: `${order.service_name} is now open for work.` });
      load();
    } catch (e: any) {
      toast({ title: 'Failed', description: e.message, variant: 'destructive' });
    }
  };

  const reject = async (order: any) => {
    await cancelServiceOrder(order.id, 'Cancelled by accounts');
    toast({ title: 'Order cancelled' });
    load();
  };

  const changeFlow = async (value: 'strict' | 'streamlined') => {
    setFlow(value);
    await setPaymentFlow(value);
    toast({ title: 'Routing updated' });
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
            <Banknote className="w-6 h-6 text-primary" /> Accounts Approvals
          </h1>
          <p className="text-muted-foreground">Release paid services to laboratory, pharmacy and other departments.</p>
        </div>
        <select value={filter} onChange={(e) => setFilter(e.target.value)} className="input-medical max-w-xs">
          <option value="pending_payment">Awaiting payment approval</option>
          <option value="released">Approved — in progress</option>
          <option value="completed">Completed</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </div>

      {isAdmin && (
        <div className="card-medical p-5">
          <div className="flex items-center gap-2 mb-2 font-semibold"><Settings2 className="w-4 h-4" /> Patient routing style</div>
          <div className="flex flex-wrap gap-3 text-sm">
            <label className="flex items-center gap-2">
              <input type="radio" checked={flow === 'strict'} onChange={() => changeFlow('strict')} />
              Accounts stop before every step
            </label>
            <label className="flex items-center gap-2">
              <input type="radio" checked={flow === 'streamlined'} onChange={() => changeFlow('streamlined')} />
              Streamlined (triage → consultation → accounts → diagnostics → review → accounts → pharmacy)
            </label>
          </div>
        </div>
      )}

      <div className="space-y-3">
        {orders.length === 0 && <p className="text-sm text-muted-foreground">Nothing in this list.</p>}
        {orders.map((o) => (
          <div key={o.id} className="card-medical p-5 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="font-semibold">{o.service_name}</p>
              <p className="text-sm text-muted-foreground">
                {o.patients?.first_name} {o.patients?.last_name} · {o.patients?.patient_code} · {o.department}
              </p>
              {o.patients?.insurance_provider && (
                <p className="text-xs text-primary mt-1">
                  Insurance: {o.patients.insurance_provider} · {o.patients.insurance_number ?? 'no number on file'}
                </p>
              )}
              <p className="text-xs text-muted-foreground mt-1">{STATUS_LABEL[o.status]}</p>
            </div>
            <div className="flex items-center gap-3">
              <span className="text-lg font-semibold">GHS {Number(o.amount).toFixed(2)}</span>
              {o.status === 'pending_payment' && (
                <>
                  <button onClick={() => approve(o)} className="btn-primary inline-flex items-center gap-2">
                    <BadgeCheck className="w-4 h-4" /> Approve & release
                  </button>
                  <button onClick={() => reject(o)} className="btn-secondary inline-flex items-center gap-2">
                    <XCircle className="w-4 h-4" /> Cancel
                  </button>
                </>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
