import { supabase } from '@/integrations/supabase/client';

type QueryResult<T = unknown> = { data: T[] | null; error: { message: string } | null };

const db = supabase as any;

async function query<T>(table: string, patientId: string, orderColumn: string, limit = 25): Promise<T[]> {
  const result: QueryResult<T> = await db
    .from(table)
    .select('*')
    .eq('patient_id', patientId)
    .order(orderColumn, { ascending: false })
    .limit(limit);

  if (result.error) throw new Error(`${table}: ${result.error.message}`);
  return result.data ?? [];
}

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

export async function buildAIClinicalContext(patientId: string): Promise<AIClinicalContext> {
  if (!patientId) throw new Error('A patient is required to build clinical context');

  const patientResult = await db.from('patients').select('*').eq('id', patientId).maybeSingle();
  if (patientResult.error) throw new Error(`patients: ${patientResult.error.message}`);
  if (!patientResult.data) throw new Error('Patient record not found');

  const [appointments, vitals, triage, encounters, labOrders, prescriptions, imagingOrders, procedureNotes, anestheticAssessments, admissions] = await Promise.all([
    query('appointments', patientId, 'scheduled_at'),
    query('vital_signs', patientId, 'recorded_at'),
    query('triage_assessments', patientId, 'created_at'),
    query('encounters', patientId, 'created_at'),
    query('lab_orders', patientId, 'created_at'),
    query('prescriptions', patientId, 'created_at'),
    query('imaging_orders', patientId, 'created_at'),
    query('procedure_notes', patientId, 'created_at'),
    query('anesthetic_assessments', patientId, 'created_at'),
    query('admissions', patientId, 'admitted_at'),
  ]);

  const latestTriage = (triage[0] as any) ?? null;
  const latestBmi = {
    value: latestTriage?.bmi != null ? Number(latestTriage.bmi) : null,
    category: latestTriage?.bmi != null
      ? latestTriage.bmi < 18.5 ? 'underweight'
        : latestTriage.bmi < 25 ? 'healthy range'
          : latestTriage.bmi < 30 ? 'overweight' : 'obesity range'
      : 'unavailable',
    recordedAt: latestTriage?.created_at ?? null,
    weightKg: latestTriage?.weight_kg != null ? Number(latestTriage.weight_kg) : null,
    heightM: latestTriage?.height_m != null ? Number(latestTriage.height_m) : null,
  };

  const labOrderIds = labOrders.map((row: any) => row.id).filter(Boolean);
  let labResults: unknown[] = [];
  if (labOrderIds.length) {
    const result = await db.from('lab_results').select('*').in('lab_order_id', labOrderIds).order('created_at', { ascending: false }).limit(100);
    if (result.error) throw new Error(`lab_results: ${result.error.message}`);
    labResults = result.data ?? [];
  }

  return {
    generatedAt: new Date().toISOString(),
    patient: patientResult.data,
    latestBmi,
    appointments,
    vitals,
    triage,
    encounters,
    labOrders,
    labResults,
    prescriptions,
    imagingOrders,
    procedureNotes,
    anestheticAssessments,
    admissions,
  };
}
