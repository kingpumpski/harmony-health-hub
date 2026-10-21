-- Scope the laboratory workspace to the user's active facility.
-- This is additive and does not backfill legacy rows or mutate clinical data.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_laboratory_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  result jsonb;
  v_department text;
  v_facility uuid := public.current_user_facility_id();
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'Select an active facility to access the laboratory workspace';
  END IF;

  SELECT NULLIF(lower(trim(p.department)), '')
    INTO v_department
  FROM public.profiles p
  WHERE p.id = v_uid;

  IF NOT (
    public.has_role(v_uid,'admin'::public.app_role)
    OR public.has_role(v_uid,'it_admin'::public.app_role)
    OR (public.has_role(v_uid,'lab_technician'::public.app_role) AND (v_department IS NULL OR v_department = 'laboratory'))
    OR public.has_role(v_uid,'practitioner'::public.app_role)
    OR (public.has_role(v_uid,'nurse'::public.app_role) AND (v_department IS NULL OR v_department IN ('laboratory','clinical')))
    OR (public.has_role(v_uid,'midwife'::public.app_role) AND (v_department IS NULL OR v_department IN ('laboratory','clinical')))
    OR (public.has_role(v_uid,'specialist_nurse'::public.app_role) AND (v_department IS NULL OR v_department IN ('laboratory','clinical')))
    OR (public.has_role(v_uid,'radiologist'::public.app_role) AND (v_department IS NULL OR v_department = 'radiology'))
  ) THEN
    RAISE EXCEPTION 'Laboratory workspace access is not permitted';
  END IF;

  _limit := LEAST(GREATEST(COALESCE(_limit, 200), 1), 500);

  SELECT jsonb_build_object(
    'patients', COALESCE((
      SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name, p.last_name)
      FROM (
        SELECT id, first_name, last_name, patient_code, email
        FROM public.patients
        WHERE COALESCE(status, 'active') <> 'inactive'
          AND facility_id = v_facility
        ORDER BY first_name, last_name
        LIMIT _limit
      ) p
    ), '[]'::jsonb),
    'catalogue', COALESCE((
      SELECT jsonb_agg(to_jsonb(c) ORDER BY c.test_name)
      FROM (
        SELECT id, test_code, test_name, category, specimen_type, unit,
               reference_low, reference_high, reference_text, default_charge,
               active, parameters
        FROM public.lab_test_catalogue
        WHERE active
        ORDER BY test_name
        LIMIT _limit
      ) c
    ), '[]'::jsonb),
    'orders', COALESCE((
      SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC)
      FROM (
        SELECT lo.id, lo.patient_id, lo.test_name, lo.test_category, lo.priority,
               lo.status, lo.created_at, lo.clinical_notes, lo.lab_test_catalogue_id
        FROM public.lab_orders lo
        JOIN public.patients p ON p.id = lo.patient_id AND p.facility_id = v_facility
        WHERE lo.facility_id = v_facility
        ORDER BY lo.created_at DESC
        LIMIT _limit
      ) o
    ), '[]'::jsonb),
    'results', COALESCE((
      SELECT jsonb_agg(to_jsonb(r) ORDER BY r.entered_at DESC)
      FROM (
        SELECT lr.id, lr.lab_order_id, lr.result_data, lr.parameter_results,
               lr.interpretation, lr.is_abnormal, lr.status, lr.entered_at,
               lr.approved_at, lr.approved_by, lr.numeric_value, lr.unit,
               lr.reference_low, lr.reference_high, lr.abnormal_flag,
               lr.patient_id
        FROM public.lab_results lr
        JOIN public.lab_orders lo ON lo.id = lr.lab_order_id
          AND lo.facility_id = v_facility
          AND lo.patient_id = lr.patient_id
        JOIN public.patients p ON p.id = lo.patient_id AND p.facility_id = v_facility
        WHERE lr.facility_id = v_facility
        ORDER BY lr.entered_at DESC
        LIMIT _limit
      ) r
    ), '[]'::jsonb)
  ) INTO result;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_laboratory_workspace(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_workspace(integer) TO authenticated;

COMMIT;
