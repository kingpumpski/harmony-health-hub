import { supabase } from '@/integrations/supabase/client';

export interface AIClinicalContext {
  generatedAt: string;
  patient: Record<string, unknown> | null;
  latestBmi: { value: number | null; category: string; recordedAt: string | null; weightKg: number | null; heightM: number | null };
  appointments: unknown[];
  vitals: unknown[];
  triage: unknown[];
  encounters: unknown[];
  labOrders: unknown[];
  labResults: unknown[];
  prescriptions: unknown[];
  imagingOrders: unknown[];
  procedureNotes: unknown[];
  anestheticAssessments: unknown[];
  admissions: unknown[];
}

/**
 * Clinical context is assembled server-side by the authenticated edge function.
 * The browser never issues direct Data API reads against protected clinical tables.
 */
export async function buildAIClinicalContext(patientId: string): Promise<AIClinicalContext> {
  if (!patientId) throw new Error('A patient is required to build clinical context');

  const { data, error } = await supabase.functions.invoke('ai-clinical-assist', {
    body: { mode: 'clinical_context', patientId },
  });

  if (error || data?.error) {
    throw new Error(data?.error ?? error?.message ?? 'Clinical context could not be assembled');
  }

  return data as AIClinicalContext;
}
