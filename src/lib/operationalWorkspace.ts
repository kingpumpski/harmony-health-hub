import { supabase } from '@/integrations/supabase/client';

type FunctionError = Error & { context?: unknown };

type WorkspaceErrorBody = {
  error?: string;
  code?: string;
  module?: string;
};

async function readFunctionError(context: unknown): Promise<WorkspaceErrorBody | null> {
  if (context instanceof Response) {
    try {
      return await context.clone().json() as WorkspaceErrorBody;
    } catch {
      return null;
    }
  }

  if (context instanceof Blob) {
    try {
      return JSON.parse(await context.text()) as WorkspaceErrorBody;
    } catch {
      return null;
    }
  }

  if (typeof context === 'string') {
    try {
      return JSON.parse(context) as WorkspaceErrorBody;
    } catch {
      return null;
    }
  }

  if (context && typeof context === 'object') {
    const candidate = context as Record<string, unknown>;
    if ('body' in candidate && typeof candidate.body === 'string') {
      try {
        return JSON.parse(candidate.body) as WorkspaceErrorBody;
      } catch {
        return null;
      }
    }
    if ('error' in candidate || 'code' in candidate || 'module' in candidate) {
      return {
        error: typeof candidate.error === 'string' ? candidate.error : undefined,
        code: typeof candidate.code === 'string' ? candidate.code : undefined,
        module: typeof candidate.module === 'string' ? candidate.module : undefined,
      };
    }
  }

  return null;
}

export async function getOperationalWorkspace(
  module: string,
  limit = 200,
): Promise<{ data: Record<string, unknown> | null; error: Error | null }> {
  const { data, error } = await supabase.functions.invoke('operational-workspace', {
    body: { module, limit },
  });

  if (error) {
    const body = await readFunctionError((error as FunctionError).context);
    if (body) {
      const detail = body.error ? String(body.error) : error.message;
      const suffix = body.module ? ` [module: ${body.module}]` : '';
      const code = body.code ? ` [${body.code}]` : '';
      return { data: null, error: new Error(`${detail}${code}${suffix}`) };
    }

    return { data: null, error: new Error(error.message) };
  }

  if (data?.error) {
    const body = data as WorkspaceErrorBody;
    const detail = body.error ? String(body.error) : 'Operational workspace query failed';
    const suffix = body.module ? ` [module: ${body.module}]` : '';
    const code = body.code ? ` [${body.code}]` : '';
    return { data: null, error: new Error(`${detail}${code}${suffix}`) };
  }

  return { data: (data ?? {}) as Record<string, unknown>, error: null };
}
