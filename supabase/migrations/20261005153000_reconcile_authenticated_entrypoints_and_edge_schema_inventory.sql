-- Reconcile authenticated workflow entrypoints and remove unintended public/test helper execution.
-- Runtime schema change applied directly to the live Supabase project first.

BEGIN;

CREATE OR REPLACE FUNCTION public.create_patient_admission(
  _patient_id uuid,
  _reason text,
  _ward text DEFAULT NULL::text,
  _bed text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'practitioner')
    OR public.has_role(auth.uid(), 'nurse')
    OR public.has_role(auth.uid(), 'midwife')
  ) THEN
    RAISE EXCEPTION 'Admission creation is not permitted';
  END IF;

  RETURN public.create_admission_workflow(_patient_id, _ward, _bed, _reason);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.create_patient_admission(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_admission(uuid,text,text,text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.hms_test_facility_id() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.hms_test_mode_enabled() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.generate_invoice_number() FROM anon;
REVOKE EXECUTE ON FUNCTION public.search_clinical_diagnoses(text,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_clinical_diagnoses(text,uuid,integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_patient_triage_history(uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_patient_triage_history(uuid,integer) TO authenticated;

COMMIT;
