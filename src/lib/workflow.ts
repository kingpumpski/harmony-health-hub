import { supabase } from '@/integrations/supabase/client';
import { notifyRoles } from '@/lib/notifications';

export type ServiceDepartment = 'laboratory' | 'imaging' | 'procedure' | 'pharmacy' | 'consultation' | 'other';
export type PaymentFlow = 'strict' | 'streamlined';
export type ServiceOrderStatus = 'pending_payment_approval' | 'released' | 'in_progress' | 'completed' | 'cancelled';

interface ServiceOrderRpcRow {
  id: string;
  department: string;
  service_name: string;
  patient_id: string;
  status: ServiceOrderStatus;
}

interface WorkflowRpcClient {
  rpc(
    functionName: string,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

const workflowRpc = supabase as unknown as WorkflowRpcClient;

export interface CreateServiceOrderInput {
  patientId: string;
  encounterId?: string | null;
  department: ServiceDepartment;
  serviceName: string;
  amount?: number;
  relatedEntityId?: string | null;
  notes?: string | null;
  requestedBy?: string | null;
  invoiceId?: string | null;
  invoiceItemId?: string | null;
  orderType?: 'lab' | 'imaging' | 'procedure' | 'drug' | null;
  serviceCode?: string | null;
}

/** Facility routing style stored in the existing facility settings schema. */
export async function getPaymentFlow(): Promise<PaymentFlow> {
  const { data, error } = await supabase
    .from('facility_settings')
    .select('payment_flow')
    .eq('id', 'default')
    .maybeSingle();
  if (error) throw error;
  return data?.payment_flow === 'strict' ? 'strict' : 'streamlined';
}

export async function setPaymentFlow(flow: PaymentFlow) {
  const { error } = await workflowRpc.rpc('set_facility_routing_mode', {
    _mode: flow === 'strict' ? 'pay_before_each_step' : 'streamlined',
  });
  if (error) throw new Error(error.message);
}

/** Every chargeable service starts blocked until Accounts releases it. */
export async function createServiceOrder(input: CreateServiceOrderInput) {
  const { data, error } = await supabase
    .from('service_orders')
    .insert({
      patient_id: input.patientId,
      encounter_id: input.encounterId ?? null,
      department: input.department,
      service_name: input.serviceName,
      amount: input.amount ?? 0,
      related_entity_id: input.relatedEntityId ?? null,
      notes: input.notes ?? null,
      requested_by: input.requestedBy ?? null,
      invoice_id: input.invoiceId ?? null,
      status: 'pending_payment_approval',
    })
    .select()
    .single();
  if (error) throw error;

  await notifyRoles(['accountant', 'front_desk'], {
    title: 'Payment approval needed',
    message: `${input.serviceName} (${input.department}) is awaiting payment approval.`,
    severity: 'warning',
    category: 'payment',
    link: '/accounts-approvals',
    relatedPatientId: input.patientId,
    relatedEntityId: data.id,
  });

  return data;
}

/** Accounts releases only through the database payment gate. */
export async function releaseServiceOrder(orderId: string, _approvedBy?: string, reason = 'Payment received') {
  const { data: rawData, error } = await workflowRpc.rpc('release_service_order', {
    _service_order_id: orderId,
    _reason: reason,
  });
  if (error) throw new Error(error.message);
  const data = rawData as ServiceOrderRpcRow;

  const roleByDept: Record<ServiceDepartment, string[]> = {
    laboratory: ['lab_technician'],
    imaging: ['lab_technician', 'practitioner'],
    pharmacy: ['pharmacist'],
    procedure: ['practitioner', 'nurse'],
    consultation: ['practitioner'],
    other: ['practitioner'],
  };

  await notifyRoles(roleByDept[data.department as ServiceDepartment] ?? ['practitioner'], {
    title: 'Service approved by accounts',
    message: `${data.service_name} has been paid for and released. You can proceed.`,
    severity: 'success',
    category: 'payment',
    relatedPatientId: data.patient_id,
    relatedEntityId: data.id,
  });

  return data;
}

export async function grantServiceOrderOverride(orderId: string, reason: string) {
  const { data, error } = await workflowRpc.rpc('grant_service_order_override', {
    _service_order_id: orderId,
    _reason: reason,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function cancelServiceOrder(orderId: string, reason = 'Cancelled by authorised staff') {
  const { data, error } = await workflowRpc.rpc('cancel_service_order', {
    _service_order_id: orderId,
    _reason: reason,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function markServiceOrderInProgress(orderId: string) {
  const { data, error } = await workflowRpc.rpc('mark_service_order_in_progress', {
    _service_order_id: orderId,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function completeServiceOrder(orderId: string) {
  const { data, error } = await workflowRpc.rpc('complete_service_order', {
    _service_order_id: orderId,
  });
  if (error) throw new Error(error.message);
  return data;
}

/** A department may work only after Accounts has released the order. */
export async function isReleased(relatedEntityId: string) {
  const { data, error } = await supabase
    .from('service_orders')
    .select('status')
    .eq('related_entity_id', relatedEntityId)
    .maybeSingle();
  if (error) throw error;
  return !data || data.status === 'released' || data.status === 'in_progress' || data.status === 'completed';
}

export const STATUS_LABEL: Record<ServiceOrderStatus, string> = {
  pending_payment_approval: 'Awaiting payment approval',
  released: 'Released to department',
  in_progress: 'In progress',
  completed: 'Completed',
  cancelled: 'Cancelled',
};
