-- Narrow AI workspace reads so the AI assistant does not depend on broad table access.

CREATE OR REPLACE FUNCTION public.get_ai_case_memory_for_diagnosis(_diagnosis text, _limit integer DEFAULT 20)
RETURNS TABLE(id uuid, diagnosis text, icd_code text, symptoms text, prescriptions jsonb, outcome text, outcome_notes text, age_group text, gender text, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_limit integer;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'radiologist') OR public.has_role(auth.uid(),'pharmacist')
  ) THEN RAISE EXCEPTION 'Not authorised'; END IF;
  IF _diagnosis IS NULL OR btrim(_diagnosis) = '' THEN RAISE EXCEPTION 'Diagnosis is required'; END IF;
  v_limit := LEAST(GREATEST(COALESCE(_limit,20),1),50);
  RETURN QUERY
  SELECT a.id,a.diagnosis,a.icd_code,a.symptoms,a.prescriptions,a.outcome,a.outcome_notes,a.age_group,a.gender,a.created_at
  FROM public.ai_case_memory a
  WHERE lower(a.diagnosis)=lower(btrim(_diagnosis))
  ORDER BY a.created_at DESC LIMIT v_limit;
END; $$;

CREATE OR REPLACE FUNCTION public.get_ai_report_requests(_patient_id uuid DEFAULT NULL, _limit integer DEFAULT 25)
RETURNS TABLE(id uuid, patient_id uuid, report_type text, requested_by uuid, status text, content text, error text, created_at timestamptz, completed_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_limit integer; v_is_owner boolean; v_is_staff boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT EXISTS(SELECT 1 FROM public.patients p WHERE p.id=_patient_id AND p.user_id=auth.uid()) INTO v_is_owner;
  SELECT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'radiologist')
  ) INTO v_is_staff;
  IF NOT (v_is_owner OR v_is_staff) THEN RAISE EXCEPTION 'Not authorised'; END IF;
  IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.patients p WHERE p.id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  v_limit := LEAST(GREATEST(COALESCE(_limit,25),1),50);
  RETURN QUERY SELECT r.id,r.patient_id,r.report_type,r.requested_by,r.status,r.content,r.error,r.created_at,r.completed_at
  FROM public.ai_report_requests r WHERE r.patient_id=_patient_id ORDER BY r.created_at DESC LIMIT v_limit;
END; $$;

REVOKE ALL ON FUNCTION public.get_ai_case_memory_for_diagnosis(text,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_ai_case_memory_for_diagnosis(text,integer) TO authenticated;
REVOKE ALL ON FUNCTION public.get_ai_report_requests(uuid,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_ai_report_requests(uuid,integer) TO authenticated;
