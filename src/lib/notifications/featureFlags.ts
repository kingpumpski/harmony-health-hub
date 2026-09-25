import { supabase } from '@/integrations/supabase/client';

export async function notificationFeatureEnabled(key: string, userId?: string): Promise<boolean> {
  const { data, error } = await supabase.rpc('notification_feature_enabled', { _key: key, _user_id: userId ?? null });
  return !error && data === true;
}