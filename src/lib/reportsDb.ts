import { supabase } from '@/integrations/supabase/client';

type QueryResult = { data: unknown; error: { message: string } | null; count?: number | null };
type ReportsQuery = PromiseLike<QueryResult> & {
  select: (columns?: string, options?: { count?: 'exact'; head?: boolean }) => ReportsQuery;
  insert: (values: unknown | unknown[]) => ReportsQuery;
  upsert: (values: unknown | unknown[], options?: { onConflict?: string }) => ReportsQuery;
  update: (values: unknown) => ReportsQuery;
  eq: (column: string, value: unknown) => ReportsQuery;
  in: (column: string, values: unknown[]) => ReportsQuery;
  gte: (column: string, value: unknown) => ReportsQuery;
  lte: (column: string, value: unknown) => ReportsQuery;
  order: (column: string, options?: { ascending?: boolean }) => ReportsQuery;
  single: () => ReportsQuery;
};

type ReportsClient = {
  from: (table: string) => ReportsQuery;
  rpc: (functionName: string, args?: Record<string, unknown>) => Promise<QueryResult>;
};

export const reportsDb = supabase as unknown as ReportsClient;
