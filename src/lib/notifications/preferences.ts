import { supabase } from '@/integrations/supabase/client';
import type { NotificationChannel, NotificationPriority } from './contracts';

export interface NotificationPreferences {
  locale: string;
  timezone: string;
  quiet_hours_start: string;
  quiet_hours_end: string;
  pause_non_critical: boolean;
  channel_preferences: Record<string, boolean>;
  category_preferences: Record<string, boolean>;
}

const DEFAULTS: NotificationPreferences = {
  locale: 'en-GH',
  timezone: 'Africa/Accra',
  quiet_hours_start: '22:00:00',
  quiet_hours_end: '07:00:00',
  pause_non_critical: false,
  channel_preferences: { in_app: true, email: false, sms: false, push: false, whatsapp: false, voice: false },
  category_preferences: { appointments: true, medication: true, clinical: true, billing: true, reviews: true, marketing: false, greetings: true, campaigns: false, wellness: true },
};

export async function resolvePreferences(userId: string): Promise<NotificationPreferences> {
  const { data, error } = await supabase.rpc('ensure_notification_preferences', { _user_id: userId });
  if (error || !data) return DEFAULTS;
  return {
    ...DEFAULTS,
    ...data,
    channel_preferences: { ...DEFAULTS.channel_preferences, ...(data.channel_preferences ?? {}) },
    category_preferences: { ...DEFAULTS.category_preferences, ...(data.category_preferences ?? {}) },
  };
}

export function isQuietHours(date: Date, timezone: string, start: string, end: string): boolean {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone: timezone, hour: '2-digit', minute: '2-digit', hour12: false }).formatToParts(date);
  const current = Number(parts.find((p) => p.type === 'hour')?.value ?? 0) * 60 + Number(parts.find((p) => p.type === 'minute')?.value ?? 0);
  const [sh, sm] = start.split(':').map(Number); const [eh, em] = end.split(':').map(Number);
  const s = sh * 60 + sm; const e = eh * 60 + em;
  return s > e ? current >= s || current < e : current >= s && current < e;
}

export function allowedChannel(channel: NotificationChannel, priority: NotificationPriority, preferences: NotificationPreferences): boolean {
  if (channel === 'in_app') return true;
  if (priority === 'critical') return true;
  if (preferences.pause_non_critical) return false;
  return preferences.channel_preferences[channel] === true;
}