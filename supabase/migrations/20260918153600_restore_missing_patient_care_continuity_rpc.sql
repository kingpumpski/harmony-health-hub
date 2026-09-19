-- Runtime reconciliation: restore the patient care continuity RPC when a production
-- migration was skipped or applied out of order. Keep the API contract server-side
-- and expose it only to authenticated clients.
CREATE OR REPLACE FUNCTION public.get_patient_care_continuity(_patient_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'referrals', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM (SELECT id,destination,specialty,reason,urgency,status,appointment_date,created_at FROM public.patient_referrals WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100) r),'[]'::jsonb),
    'transitions', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM (SELECT id,transition_type,status,destination,summary,follow_up_required,follow_up_date,created_at,completed_at FROM public.care_transitions WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100) r),'[]'::jsonb),
    'mar', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.scheduled_at DESC) FROM (SELECT id,medication_name,dose,route,status,scheduled_at,administered_at,reason FROM public.medication_administrations WHERE patient_id=_patient_id ORDER BY scheduled_at DESC LIMIT 100) r),'[]'::jsonb),
    'emergency', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.arrival_time DESC) FROM (SELECT id,chief_complaint,acuity,arrival_mode,status,arrival_time,created_at,disposition FROM public.emergency_cases WHERE patient_id=_patient_id ORDER BY arrival_time DESC LIMIT 100) r),'[]'::jsonb),
    'theatre', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.scheduled_start DESC) FROM (SELECT id,procedure_name,theatre_name,scheduled_start,urgency,status,anesthetist_id,created_at FROM public.theatre_cases WHERE patient_id=_patient_id ORDER BY scheduled_start DESC LIMIT 100) r),'[]'::jsonb),
    'transfusion', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM (SELECT id,blood_product,unit_identifier,blood_group,status,started_at,completed_at,reaction_observed,reaction_notes,created_at FROM public.transfusion_records WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100) r),'[]'::jsonb),
    'claims', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM (SELECT id,payer_name,member_number,amount_claimed,amount_approved,amount_paid,status,service_from,service_to,rejection_reason,created_at FROM public.insurance_claims WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100) r),'[]'::jsonb),
    'admissions', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.admitted_at DESC) FROM (SELECT id,status,reason,admitted_at,discharged_at,discharge_summary FROM public.admissions WHERE patient_id=_patient_id ORDER BY admitted_at DESC LIMIT 100) r),'[]'::jsonb)
  );
$$;

REVOKE EXECUTE ON FUNCTION public.get_patient_care_continuity(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_patient_care_continuity(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_patient_care_continuity(UUID) TO authenticated;
