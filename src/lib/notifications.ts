import { supabase } from '@/integrations/supabase/client';

export type NotificationSeverity = 'info' | 'success' | 'warning' | 'critical';
export type NotificationCategory =
  | 'lab' | 'payment' | 'appointment' | 'encounter'
  | 'triage' | 'prescription' | 'telemedicine' | 'admission' | 'other';

export type StaffRole =
  | 'admin' | 'practitioner' | 'nurse' | 'midwife'
  | 'lab_technician' | 'pharmacist' | 'accountant' | 'front_desk' | 'canteen' | 'patient';

interface NotifyOptions {
  recipientRole?: StaffRole;
  recipientUserId?: string;
  title: string;
  message: string;
  severity?: NotificationSeverity;
  category?: NotificationCategory;
  link?: string;
  relatedPatientId?: string;
  relatedEntityId?: string;
  metadata?: Record<string, unknown>;
}

/** Insert a single notification row. */
export async function notify(opts: NotifyOptions) {
  return supabase.from('notifications').insert({
    recipient_role: (opts.recipientRole ?? null) as any,
    recipient_user_id: opts.recipientUserId ?? null,
    title: opts.title,
    message: opts.message,
    severity: opts.severity ?? 'info',
    category: opts.category ?? 'other',
    link: opts.link ?? null,
    related_patient_id: opts.relatedPatientId ?? null,
    related_entity_id: opts.relatedEntityId ?? null,
    metadata: (opts.metadata ?? {}) as any,
  });
}

/** Broadcast the same notification to multiple roles at once. */
export async function notifyRoles(roles: StaffRole[], opts: Omit<NotifyOptions, 'recipientRole' | 'recipientUserId'>) {
  const rows = roles.map((role) => ({
    recipient_role: role as any,
    title: opts.title,
    message: opts.message,
    severity: opts.severity ?? 'info',
    category: opts.category ?? 'other',
    link: opts.link ?? null,
    related_patient_id: opts.relatedPatientId ?? null,
    related_entity_id: opts.relatedEntityId ?? null,
    metadata: (opts.metadata ?? {}) as any,
  }));
  return supabase.from('notifications').insert(rows as any);
}

/** Invoke an edge function for richer notifications (email + multi-recipient). Best-effort. */
export async function invokeNotifier(name: string, body: Record<string, unknown>) {
  try {
    await supabase.functions.invoke(name, { body });
  } catch (err) {
    console.warn(`[invokeNotifier] ${name} failed`, err);
  }
}
