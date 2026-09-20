CREATE OR REPLACE FUNCTION public.get_ai_clinical_context(_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE v_role public.app_role; v_patient jsonb; v_result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT role INTO v_role FROM public.profiles WHERE id=auth.uid();
 IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
 SELECT to_jsonb(p) - 'national_id' - 'ghana_card_number' - 'passport_number' - 'insurance_member_number' INTO v_patient FROM public.patients p WHERE p.id=_patient_id;
 IF v_patient IS NULL THEN RAISE EXCEPTION 'Patient record not found'; END IF;
 SELECT jsonb_build_object('patient',v_patient,'appointments',COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.scheduled_at DESC) FROM public.appointments a WHERE a.patient_id=_patient_id LIMIT 25),'[]'::jsonb),'vitals',COALESCE((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.recorded_at DESC) FROM public.vital_signs v WHERE v.patient_id=_patient_id LIMIT 25),'[]'::jsonb),'triage',COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC) FROM public.triage_assessments t WHERE t.patient_id=_patient_id LIMIT 25),'[]'::jsonb),'encounters',COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.created_at DESC) FROM public.encounters e WHERE e.patient_id=_patient_id LIMIT 25),'[]'::jsonb)) INTO v_result;
 RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.get_ai_clinical_context(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_ai_clinical_context(uuid) TO authenticated;
