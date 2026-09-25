import { supabase } from '@/integrations/supabase/client';

export async function scheduleNotification(input: {
  userId: string;
  eventName: string;
  templateKey: string;
  payload: Record<string, unknown>;
  runAt: string;
  timezone?: string;
  locale?: string;
  channels?: string[];
  priority?: string;
  idempotencyKey: string;
}) {
  const { data, error } = await supabase.from('scheduled_notifications').insert({
    user_id: input.userId,
    event_name: input.eventName,
    template_key: input.templateKey,
    payload: input.payload,
    run_at: input.runAt,
    timezone: input.timezone ?? 'Africa/Accra',
    locale: input.locale ?? 'en-GH',
    channels: input.channels ?? ['in_app'],
    priority: input.priority ?? 'medium',
    idempotency_key: input.idempotencyKey,
  }).select('id').single();
  if (error) throw error;
  return data.id as string;
}