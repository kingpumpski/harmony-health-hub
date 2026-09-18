import { supabase } from '@/integrations/supabase/client';

export interface StaffPatient {
  id: string;
  patient_code: string;
  first_name: string;
  last_name: string;
  phone: string | null;
  ghana_card_number: string | null;
  status: string | null;
  insurance_provider: string | null;
  insurance_number: string | null;
}

export async function searchPatientDirectory(query = '', limit = 300): Promise<{ data: StaffPatient[]; error: Error | null }> {
  const { data, error } = await supabase.rpc('search_patient_directory' as never, {
    _query: query.trim() || null,
    _limit: limit,
  } as never);
  return { data: (data ?? []) as StaffPatient[], error: error ? new Error(error.message) : null };
}

export async function getPatientDirectoryRecord(patientId: string): Promise<{ data: StaffPatient | null; error: Error | null }> {
  const { data, error } = await supabase.rpc('get_patient_directory_record' as never, { _patient_id: patientId } as never);
  const rows = (data ?? []) as StaffPatient[];
  return { data: rows[0] ?? null, error: error ? new Error(error.message) : null };
}