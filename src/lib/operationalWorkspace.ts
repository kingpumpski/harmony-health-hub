import { supabase } from '@/integrations/supabase/client';

export async function getOperationalWorkspace(module: string, limit = 200): Promise<{ data: Record<string, unknown> | null; error: Error | null }> {
  const { data, error } = await supabase.functions.invoke('operational-workspace', { body: { module, limit } });
  if (error) return { data: null, error: new Error(error.message) };
  if (data?.error) return { data: null, error: new Error(String(data.error)) };
  return { data: (data ?? {}) as Record<string, unknown>, error: null };
}
