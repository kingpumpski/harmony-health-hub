import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import {
  completeServiceOrder,
  markServiceOrderInProgress,
  STATUS_LABEL,
  type ServiceOrderStatus,
} from '@/lib/workflow';
import { CheckCircle2, ClipboardList, PlayCircle, RefreshCw } from 'lucide-react';

interface QueueRow {
  id: string;
  department: string;
  status: 'queued' | 'claimed' | 'completed' | 'cancelled';
  queued_at: string;
  claimed_at: string | null;
  service_orders: {
    id: string;
    service_name: string;
    department: string;
    amount: number | string;
    status: ServiceOrderStatus;
    patient_id: string;
    patients?: {
      first_name: string | null;
      last_name: string | null;
      patient_code: string | null;
    } | null;
  } | null;
}

export default function DepartmentQueue() {
  const { user } = useAuth();
  const [department, setDepartment] = useState<string>('');
  const [rows, setRows] = useState<QueueRow[]>([]);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user?.id) return;
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('department')
      .eq('id', user.id)
      .maybeSingle();
    if (profileError) {
      toast({ title: 'Could not load department', description: profileError.message, variant: 'destructive' });
      return;
    }

    const currentDepartment = profile?.department?.trim() ?? '';
    setDepartment(currentDepartment);
    if (!currentDepartment) {
      setRows([]);
      return;
    }

    const { data, error } = await supabase
      .from('department_queues')
      .select('id,department,status,queued_at,claimed_at,service_orders(id,service_name,department,amount,status,patient_id,patients(first_name,last_name,patient_code))')
      .eq('department', currentDepartment)
      .in('status', ['queued', 'claimed'])
      .order('queued_at', { ascending: true });
    if (error) {
      toast({ title: 'Could not load department queue', description: error.message, variant: 'destructive' });
      return;
    }
    setRows((data ?? []) as QueueRow[]);
  }, [user?.id]);

  useEffect(() => { void load(); }, [load]);

  const start = async (orderId: string) => {
    setBusyId(orderId);
    try {
      await markServiceOrderInProgress(orderId);
      toast({ title: 'Order started' });
      await load();
    } catch (error) {
      toast({ title: 'Could not start order', description: error instanceof Error ? error.message : 'The order is not available.', variant: 'destructive' });
    } finally {
      setBusyId(null);
    }
  };

  const complete = async (orderId: string) => {
    setBusyId(orderId);
    try {
      await completeServiceOrder(orderId);
      toast({ title: 'Order completed' });
      await load();
    } catch (error) {
      toast({ title: 'Could not complete order', description: error instanceof Error ? error.message : 'The order could not be completed.', variant: 'destructive' });
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
            <ClipboardList className="w-6 h-6 text-primary" /> Department Queue
          </h1>
          <p className="text-muted-foreground">
            {department ? `Released work for ${department}.` : 'Your profile is not assigned to a department.'}
          </p>
        </div>
        <button onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2 self-start">
          <RefreshCw className="w-4 h-4" /> Refresh
        </button>
      </div>

      {!department && (
        <div className="card-medical p-5 text-sm text-muted-foreground">
          Ask an administrator to assign your clinical department before using the service queue.
        </div>
      )}

      {department && rows.length === 0 && (
        <div className="card-medical p-8 text-center text-sm text-muted-foreground">
          No released service orders are waiting for your department.
        </div>
      )}

      <div className="space-y-3">
        {rows.map((row) => {
          const order = row.service_orders;
          if (!order) return null;
          const patient = order.patients;
          const busy = busyId === order.id;
          return (
            <div key={row.id} className="card-medical p-5 flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <p className="font-semibold">{order.service_name}</p>
                  <span className="text-xs rounded-full bg-muted px-2 py-1">{STATUS_LABEL[order.status]}</span>
                </div>
                <p className="text-sm text-muted-foreground">
                  {patient?.first_name} {patient?.last_name} · {patient?.patient_code}
                </p>
                <p className="text-xs text-muted-foreground mt-1">Queued {new Date(row.queued_at).toLocaleString()}</p>
              </div>
              <div className="flex flex-wrap gap-2">
                {order.status === 'released' && (
                  <button disabled={busy} onClick={() => void start(order.id)} className="btn-primary inline-flex items-center gap-2 disabled:opacity-50">
                    <PlayCircle className="w-4 h-4" /> Start
                  </button>
                )}
                {order.status === 'in_progress' && (
                  <button disabled={busy} onClick={() => void complete(order.id)} className="btn-primary inline-flex items-center gap-2 disabled:opacity-50">
                    <CheckCircle2 className="w-4 h-4" /> Complete
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
