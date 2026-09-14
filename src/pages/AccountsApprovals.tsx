import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import {
  cancelServiceOrder,
  grantServiceOrderOverride,
  releaseServiceOrder,
  getPaymentFlow,
  setPaymentFlow,
  STATUS_LABEL,
  type PaymentFlow,
  type ServiceOrderStatus,
} from '@/lib/workflow';
import { BadgeCheck, Banknote, ShieldCheck, XCircle, Settings2 } from 'lucide-react';

interface AccountsOrder {
  id: string;
  patient_id: string;
  service_name: string;
  department: string;
  amount: number | string;
  status: ServiceOrderStatus;
  invoice_id: string | null;
  patients?: {
    first_name: string | null;
    last_name: string | null;
    patient_code: string | null;
    insurance_provider: string | null;
    insurance_number: string | null;
    partner_company: string | null;
  } | null;
}

export default function AccountsApprovals() {
  const { user } = useAuth();
  const [orders, setOrders] = useState<AccountsOrder[]>([]);
  const [flow, setFlow] = useState<PaymentFlow>('streamlined');
  const [filter, setFilter] = useState<ServiceOrderStatus>('pending_payment_approval');
  const [busyId, setBusyId] = useState<string | null>(null);
  const isAdmin = user?.role === 'admin';

  const load = useCallback(async () => {
    const { data, error } = await supabase
      .from('service_orders')
      .select('id,patient_id,service_name,department,amount,status,invoice_id,patients(first_name,last_name,patient_code,insurance_provider,insurance_number,partner_company)')
      .eq('status', filter)
      .order('created_at', { ascending: false })
      .limit(100);
    if (error) {
      toast({ title: 'Could not load approvals', description: error.message, variant: 'destructive' });
      return;
    }
    setOrders((data ?? []) as AccountsOrder[]);
  }, [filter]);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    getPaymentFlow().then(setFlow).catch((error: Error) => {
      toast({ title: 'Could not load routing settings', description: error.message, variant: 'destructive' });
    });
  }, []);

  const approve = async (order: AccountsOrder) => {
    setBusyId(order.id);
    try {
      await releaseServiceOrder(order.id, user?.id);
      toast({ title: 'Released to department', description: `${order.service_name} is now open for work.` });
      await load();
    } catch (error) {
      toast({ title: 'Release blocked', description: error instanceof Error ? error.message : 'Payment approval is required.', variant: 'destructive' });
    } finally {
      setBusyId(null);
    }
  };

  const override = async (order: AccountsOrder) => {
    const reason = window.prompt('Enter the Accounts override reason:')?.trim();
    if (!reason) return;
    setBusyId(order.id);
    try {
      await grantServiceOrderOverride(order.id, reason);
      await releaseServiceOrder(order.id, user?.id, `Override: ${reason}`);
      toast({ title: 'Override approved', description: `${order.service_name} has been released.` });
      await load();
    } catch (error) {
      toast({ title: 'Override failed', description: error instanceof Error ? error.message : 'Unable to grant override.', variant: 'destructive' });
    } finally {
      setBusyId(null);
    }
  };

  const reject = async (order: AccountsOrder) => {
    setBusyId(order.id);
    try {
      await cancelServiceOrder(order.id, 'Cancelled by Accounts');
      toast({ title: 'Order cancelled' });
      await load();
    } catch (error) {
      toast({ title: 'Cancellation failed', description: error instanceof Error ? error.message : 'Unable to cancel order.', variant: 'destructive' });
    } finally {
      setBusyId(null);
    }
  };

  const activateCoverage = async (order: AccountsOrder) => {
    setBusyId(order.id);
    try {
      const { error } = await supabase.rpc('activate_patient_visit_coverage' as never, {
        _patient_id: order.patient_id,
        _source: 'accounts',
        _appointment_id: null,
      } as never);
      if (error) throw error;
      toast({ title: 'Daily coverage activated', description: 'New eligible orders created today will release automatically.' });
    } catch (error) {
      toast({ title: 'Coverage activation failed', description: error instanceof Error ? error.message : 'Unable to activate coverage.', variant: 'destructive' });
    } finally {
      setBusyId(null);
    }
  };

  const changeFlow = async (value: PaymentFlow) => {
    try {
      await setPaymentFlow(value);
      setFlow(value);
      toast({ title: 'Routing updated' });
    } catch (error) {
      toast({ title: 'Routing update failed', description: error instanceof Error ? error.message : 'Unable to update routing.', variant: 'destructive' });
    }
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
        <select value={filter} onChange={(e) => setFilter(e.target.value as ServiceOrderStatus)} className="input-medical max-w-xs">
          <option value="pending_payment_approval">Awaiting payment approval</option>
          <option value="released">Released</option>
          <option value="in_progress">In progress</option>
          <option value="completed">Completed</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </div>

      {isAdmin && (
        <div className="card-medical p-5">
          <div className="flex items-center gap-2 mb-2 font-semibold"><Settings2 className="w-4 h-4" /> Patient routing style</div>
          <div className="flex flex-wrap gap-3 text-sm">
            <label className="flex items-center gap-2">
              <input type="radio" checked={flow === 'strict'} onChange={() => void changeFlow('strict')} />
              Accounts stop before every step
            </label>
            <label className="flex items-center gap-2">
              <input type="radio" checked={flow === 'streamlined'} onChange={() => void changeFlow('streamlined')} />
              Streamlined routing between clinical steps
            </label>
          </div>
        </div>
      )}

      <div className="space-y-3">
        {orders.length === 0 && <p className="text-sm text-muted-foreground">Nothing in this list.</p>}
        {orders.map((order) => {
          const patient = order.patients;
          const busy = busyId === order.id;
          return (
            <div key={order.id} className="card-medical p-5 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
              <div>
                <p className="font-semibold">{order.service_name}</p>
                <p className="text-sm text-muted-foreground">
                  {patient?.first_name} {patient?.last_name} · {patient?.patient_code} · {order.department}
                </p>
                {patient?.insurance_provider && (
                  <p className="text-xs text-primary mt-1">
                    Insurance: {patient.insurance_provider} · {patient.insurance_number ?? 'no number on file'}
                  </p>
                )}
                <p className="text-xs text-muted-foreground mt-1">{STATUS_LABEL[order.status]}</p>
              </div>
              <div className="flex flex-wrap items-center gap-3">
                <span className="text-lg font-semibold">GHS {Number(order.amount).toFixed(2)}</span>
                {order.status === 'pending_payment_approval' && (
                  <>
                    {(patient?.insurance_provider || patient?.partner_company) && <button disabled={busy} onClick={() => void activateCoverage(order)} className="btn-secondary inline-flex items-center gap-2 disabled:opacity-50">
                      <ShieldCheck className="w-4 h-4" /> Activate today's coverage
                    </button>}
                    <button disabled={busy} onClick={() => void approve(order)} className="btn-primary inline-flex items-center gap-2 disabled:opacity-50">
                      <BadgeCheck className="w-4 h-4" /> Approve & release
                    </button>
                    <button disabled={busy} onClick={() => void override(order)} className="btn-secondary inline-flex items-center gap-2 disabled:opacity-50">
                      <ShieldCheck className="w-4 h-4" /> Override
                    </button>
                    <button disabled={busy} onClick={() => void reject(order)} className="btn-secondary inline-flex items-center gap-2 disabled:opacity-50">
                      <XCircle className="w-4 h-4" /> Cancel
                    </button>
                  </>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
