import { supabase } from '@/integrations/supabase/client';
import { notifyRoles } from '@/lib/notifications';

export type ServiceDepartment = 'laboratory' | 'imaging' | 'procedure' | 'pharmacy' | 'consultation' | 'other';

export interface CreateServiceOrderInput {
  patientId: string;
  encounterId?: string | null;
  department: ServiceDepartment;
  serviceName: string;
  amount?: number;
  relatedEntityId?: string | null;
  notes?: string | null;
  requestedBy?: string | null;
}

/** Facility routing style: 'strict' = accounts before every step, 'streamlined' = fewer accounts stops. */
export async function getPaymentFlow(): Promise<'strict' | 'streamlined'> {
  const { data } = await supabase.from('facility_settings').select('payment_flow').eq('id', 'default').maybeSingle();
  return (data?.payment_flow as 'strict' | 'streamlined') ?? 'streamlined';
}

export async function setPaymentFlow(flow: 'strict' | 'streamlined') {
  return supabase.from('facility_settings').update({ payment_flow: flow }).eq('id', 'default');
}

/**
 * Every chargeable service is created as pending until accounts releases it.
 * Returns the created service order row.
 */
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
      status: 'pending_payment',
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

/** Accounts releases the order to the department. */
export async function releaseServiceOrder(orderId: string, approvedBy?: string) {
  const { data, error } = await supabase
    .from('service_orders')
    .update({ status: 'released', approved_by: approvedBy ?? null, approved_at: new Date().toISOString() })
    .eq('id', orderId)
    .select()
    .single();
  if (error) throw error;

  const roleByDept: Record<string, any[]> = {
    laboratory: ['lab_technician'],
    imaging: ['lab_technician', 'practitioner'],
    pharmacy: ['pharmacist'],
    procedure: ['practitioner', 'nurse'],
    consultation: ['practitioner'],
    other: ['practitioner'],
  };

  await notifyRoles(roleByDept[data.department] ?? ['practitioner'], {
    title: 'Service approved by accounts',
    message: `${data.service_name} has been paid for and released. You can proceed.`,
    severity: 'success',
    category: 'payment',
    relatedPatientId: data.patient_id,
    relatedEntityId: data.id,
  });

  return data;
}

export async function cancelServiceOrder(orderId: string, reason?: string) {
  return supabase.from('service_orders').update({ status: 'cancelled', notes: reason ?? null }).eq('id', orderId);
}

export async function completeServiceOrder(orderId: string) {
  return supabase
    .from('service_orders')
    .update({ status: 'completed', completed_at: new Date().toISOString() })
    .eq('id', orderId);
}

/** Is a department allowed to work on this related record yet? */
export async function isReleased(relatedEntityId: string) {
  const { data } = await supabase
    .from('service_orders')
    .select('status')
    .eq('related_entity_id', relatedEntityId)
    .maybeSingle();
  return !data || data.status === 'released' || data.status === 'completed';
}

export const STATUS_LABEL: Record<string, string> = {
  pending_payment: 'Awaiting payment approval',
  released: 'Approved — in progress',
  completed: 'Completed',
  cancelled: 'Cancelled',
};
