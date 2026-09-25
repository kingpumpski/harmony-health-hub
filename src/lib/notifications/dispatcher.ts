import { supabase } from '@/integrations/supabase/client';
import type { NotificationEventEnvelope } from './contracts';
import { notificationFeatureEnabled } from './featureFlags';

export async function dispatchNotification<T extends Record<string, unknown>>(event: NotificationEventEnvelope<T>) {
  const family = event.event_name.startsWith('appointment_') ? 'appointments'
    : event.event_name.startsWith('medication_') ? 'medication'
    : event.event_name.includes('lab') || event.event_name.includes('vitals') ? 'clinical'
    : event.event_name.includes('birthday') || event.event_name.includes('seasonal') ? 'wellness'
    : 'in_app';
  const enabled = await notificationFeatureEnabled(`notifications.${family}`, event.user_id);
  if (!enabled && event.priority !== 'critical' && family !== 'in_app') return { queued: false as const, reason: 'feature_disabled' as const };

  const { data, error } = await supabase.rpc('enqueue_notification_v2', {
    _event_name: event.event_name,
    _user_id: event.user_id,
    _payload: event.payload,
    _template_key: event.template_key,
    _channels: event.channels ?? ['in_app'],
    _priority: event.priority,
    _scheduled_for: event.occurred_at,
    _idempotency_key: event.idempotency_key ?? event.event_id,
    _tenant_id: event.tenant_id ?? null,
    _locale: event.locale ?? null,
    _timezone: event.timezone ?? null,
  } as never);
  if (error) throw error;
  return { queued: true as const, queueId: data as string };
}

export async function markRead(notificationId: string) {
  const { error } = await supabase.rpc('mark_notification_read', { _notification_id: notificationId });
  if (error) throw error;
}