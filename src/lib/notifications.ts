import { supabase } from '@/integrations/supabase/client';

export type NotificationSeverity = 'info' | 'success' | 'warning' | 'critical';
export type NotificationCategory = 'lab' | 'payment' | 'appointment' | 'encounter' | 'triage' | 'prescription' | 'telemedicine' | 'admission' | 'other';
export type StaffRole = 'admin' | 'practitioner' | 'nurse' | 'midwife' | 'specialist_nurse' | 'lab_technician' | 'radiologist' | 'pharmacist' | 'accountant' | 'front_desk' | 'canteen' | 'patient';
interface NotifyOptions { recipientRole?: StaffRole; recipientUserId?: string; title:string; message:string; severity?:NotificationSeverity; category?:NotificationCategory; link?:string; relatedPatientId?:string; relatedEntityId?:string; metadata?:Record<string,unknown> }

async function createWorkflowNotification(opts: NotifyOptions) {
  return supabase.rpc('create_workflow_notification', {
    _recipient_role: opts.recipientRole ?? null,
    _recipient_user_id: opts.recipientUserId ?? null,
    _title: opts.title,
    _message: opts.message,
    _severity: opts.severity ?? 'info',
    _category: opts.category ?? 'other',
    _link: opts.link ?? null,
    _related_patient_id: opts.relatedPatientId ?? null,
    _related_entity_id: opts.relatedEntityId ?? null,
    _metadata: opts.metadata ?? {},
  } as never);
}

export async function notify(opts:NotifyOptions) {
  return createWorkflowNotification(opts);
}

export async function notifyRoles(roles:StaffRole[],opts:Omit<NotifyOptions,'recipientRole'|'recipientUserId'>) {
  const results = await Promise.all(roles.map((role) => createWorkflowNotification({ ...opts, recipientRole: role })));
  const error = results.find((result) => result.error)?.error ?? null;
  return { data: results.map((result) => result.data).filter(Boolean), error };
}

export async function invokeNotifier(name:string,body:Record<string,unknown>) {
  try { await supabase.functions.invoke(name,{body}); }
  catch(err) { console.warn(`[invokeNotifier] ${name} failed`,err); }
}
