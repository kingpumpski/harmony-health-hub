import { supabase } from '@/integrations/supabase/client';

type FunctionError = Error & { context?: Response };

export async function getOperationalWorkspace(module: string, limit = 200): Promise<{ data: Record<string, unknown> | null; error: Error | null }> {
  const { data, error } = await supabase.functions.invoke('operational-workspace', { body: { module, limit } });
  if (error) {
    const context = (error as FunctionError).context;
    if (context instanceof Response) {
      try {
        const body = await context.clone().json() as { error?: string; code?: string; module?: string };
        const detail = body?.error ? String(body.error) : error.message;
        const suffix = body?.module ? ` [module: ${body.module}]` : '';
        const code = body?.code ? ` [${body.code}]` : '';
        return { data: null, error: new Error(`${detail}${code}${suffix}`) };
      } catch {
        // Fall back to the SDK error when the response body is not JSON.
      }
    }
    return { data: null, error: new Error(error.message) };
  }
  if (data?.error) return { data: null, error: new Error(String(data.error)) };
  return { data: (data ?? {}) as Record<string, unknown>, error: null };
}
