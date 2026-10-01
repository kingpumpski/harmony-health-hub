BEGIN;

-- Diagnostic department workspaces are operational surfaces, not general clinical
-- report readers. Only the department team and administrators may call them.
CREATE OR REPLACE FUNCTION public.get_laboratory_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  result jsonb;
  v_department text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT NULLIF(lower(trim(p.department)), '')
    INTO v_department
  FROM public.profiles p
  WHERE p.id = auth.uid();

  IF NOT (
    public.has_role(auth.uid(), 'admin')
    OR (
      public.has_role(auth.uid(), 'lab_technician')
      AND (v_department IS NULL OR v_department = 'laboratory')
    )
  ) THEN
    RAISE EXCEPTION 'Laboratory operational workspace access is not permitted';
  END IF;

  _limit := LEAST(GREATEST(COALESCE(_limit, 200), 1), 500);

  SELECT jsonb_build_object(
    'patients', COALESCE((
      SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name, p.last_name)
      FROM (
        SELECT id, first_name, last_name, patient_code
        FROM public.patients
        WHERE status <> 'inactive'
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
        SELECT id, patient_id, test_name, test_category, priority, status,
               created_at, clinical_notes, lab_test_catalogue_id
        FROM public.lab_orders
        ORDER BY created_at DESC
        LIMIT _limit
      ) o
    ), '[]'::jsonb),
    'results', COALESCE((
      SELECT jsonb_agg(to_jsonb(r) ORDER BY r.entered_at DESC)
      FROM (
        SELECT id, lab_order_id, result_data, parameter_results, interpretation,
               is_abnormal, status, entered_at, approved_at, approved_by,
               numeric_value, unit, reference_low, reference_high, abnormal_flag
        FROM public.lab_results
        ORDER BY entered_at DESC
        LIMIT _limit
      ) r
    ), '[]'::jsonb)
  ) INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_laboratory_workspace(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_workspace(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_imaging_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public'
AS $$
DECLARE
  result jsonb;
  v_department text;
  v_radiologist boolean;
  v_technician boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT NULLIF(lower(trim(p.department)), '')
    INTO v_department
  FROM public.profiles p
  WHERE p.id = auth.uid();

  v_radiologist := public.has_role(auth.uid(), 'radiologist');
  v_technician := public.has_role(auth.uid(), 'radiology_technician');

  IF NOT (
    public.has_role(auth.uid(), 'admin')
    OR (v_radiologist AND (v_department IS NULL OR v_department = 'radiology'))
    OR (v_technician AND (v_department IS NULL OR v_department = 'radiology'))
  ) THEN
    RAISE EXCEPTION 'Imaging operational workspace access is not permitted';
  END IF;

  _limit := LEAST(GREATEST(COALESCE(_limit, 200), 1), 500);

  SELECT jsonb_build_object(
    'patients', COALESCE((
      SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name, p.last_name)
      FROM (
        SELECT id, first_name, last_name, patient_code
        FROM public.patients
        WHERE status <> 'inactive'
        ORDER BY first_name, last_name
        LIMIT _limit
      ) p
    ), '[]'::jsonb),
    'orders', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (
        SELECT io.id, io.patient_id, io.encounter_id, io.modality, io.study_name,
               io.body_site, io.priority, io.clinical_indication, io.amount,
               io.status, io.service_order_id, io.requested_by, io.performed_by,
               io.report, io.impression, io.created_at, io.updated_at,
               jsonb_build_object(
                 'id', p.id,
                 'first_name', p.first_name,
                 'last_name', p.last_name,
                 'patient_code', p.patient_code
               ) AS patient
        FROM public.imaging_orders io
        JOIN public.patients p ON p.id = io.patient_id
        WHERE io.status <> 'cancelled'
        ORDER BY io.created_at DESC
        LIMIT _limit
      ) x
    ), '[]'::jsonb)
  ) INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_imaging_workspace(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_imaging_workspace(integer) TO authenticated;

-- Clinician-facing laboratory report projection: approved results only, with no
-- catalogue, patient directory, unapproved orders, or department queue payload.
CREATE OR REPLACE FUNCTION public.get_clinician_lab_results(_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid;
  result jsonb;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'practitioner')
    OR public.has_role(uid, 'nurse')
    OR public.has_role(uid, 'midwife')
    OR public.has_role(uid, 'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Clinical report access is not permitted';
  END IF;

  v_facility := public.current_user_facility_id();
  _limit := LEAST(GREATEST(COALESCE(_limit, 100), 1), 300);

  SELECT COALESCE(jsonb_agg(row_data ORDER BY approved_at DESC), '[]'::jsonb)
  INTO result
  FROM (
    SELECT
      r.approved_at,
      jsonb_build_object(
        'id', r.id,
        'lab_order_id', o.id,
        'patient_id', o.patient_id,
        'encounter_id', o.encounter_id,
        'test_name', o.test_name,
        'test_category', o.test_category,
        'priority', COALESCE(o.priority, 'routine'),
        'clinical_notes', o.clinical_notes,
        'result_data', r.result_data,
        'parameter_results', r.parameter_results,
        'result_text', COALESCE(NULLIF(r.result, ''), r.result_data ->> 'value'),
        'interpretation', r.interpretation,
        'is_abnormal', COALESCE(r.is_abnormal, false),
        'status', r.status,
        'entered_at', r.entered_at,
        'approved_at', r.approved_at,
        'numeric_value', r.numeric_value,
        'unit', r.unit,
        'reference_low', r.reference_low,
        'reference_high', r.reference_high,
        'abnormal_flag', r.abnormal_flag,
        'patients', jsonb_build_object(
          'id', p.id,
          'first_name', p.first_name,
          'last_name', p.last_name,
          'patient_code', p.patient_code
        )
      ) AS row_data
    FROM public.lab_results r
    JOIN public.lab_orders o ON o.id = r.lab_order_id
    JOIN public.patients p ON p.id = o.patient_id
    LEFT JOIN public.encounters e ON e.id = o.encounter_id
    WHERE r.status = 'approved'
      AND o.status = 'approved'
      AND (
        (
          COALESCE(o.facility_id, e.facility_id, p.facility_id) IS NOT NULL
          AND public.current_user_has_facility_access(
            COALESCE(o.facility_id, e.facility_id, p.facility_id)
          )
        )
        OR (
          COALESCE(o.facility_id, e.facility_id, p.facility_id) IS NULL
          AND (o.ordered_by = uid OR e.practitioner_id = uid)
        )
      )
    ORDER BY r.approved_at DESC NULLS LAST
    LIMIT _limit
  ) approved_results;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_clinician_lab_results(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_clinician_lab_results(integer) TO authenticated;

-- Imaging completion is the authorised report-finalisation state in the current
-- imaging lifecycle. Only completed reports are returned to clinical readers.
CREATE OR REPLACE FUNCTION public.get_clinician_imaging_results(_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid;
  result jsonb;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'practitioner')
    OR public.has_role(uid, 'nurse')
    OR public.has_role(uid, 'midwife')
    OR public.has_role(uid, 'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Clinical report access is not permitted';
  END IF;

  v_facility := public.current_user_facility_id();
  _limit := LEAST(GREATEST(COALESCE(_limit, 100), 1), 300);

  SELECT COALESCE(jsonb_agg(row_data ORDER BY updated_at DESC), '[]'::jsonb)
  INTO result
  FROM (
    SELECT
      io.updated_at,
      jsonb_build_object(
        'id', io.id,
        'patient_id', io.patient_id,
        'study_name', io.study_name,
        'modality', io.modality,
        'priority', COALESCE(io.priority, 'routine'),
        'report', io.report,
        'impression', io.impression,
        'encounter_id', io.encounter_id,
        'created_at', io.created_at,
        'updated_at', io.updated_at,
        'patients', jsonb_build_object(
          'id', p.id,
          'first_name', p.first_name,
          'last_name', p.last_name,
          'patient_code', p.patient_code
        )
      ) AS row_data
    FROM public.imaging_orders io
    JOIN public.patients p ON p.id = io.patient_id
    LEFT JOIN public.encounters e ON e.id = io.encounter_id
    WHERE io.status = 'completed'
      AND (NULLIF(trim(COALESCE(io.report, '')), '') IS NOT NULL
           OR NULLIF(trim(COALESCE(io.impression, '')), '') IS NOT NULL)
      AND (
        (
          COALESCE(io.facility_id, e.facility_id, p.facility_id) IS NOT NULL
          AND public.current_user_has_facility_access(
            COALESCE(io.facility_id, e.facility_id, p.facility_id)
          )
        )
        OR (
          COALESCE(io.facility_id, e.facility_id, p.facility_id) IS NULL
          AND (io.requested_by = uid OR e.practitioner_id = uid)
        )
      )
    ORDER BY io.updated_at DESC
    LIMIT _limit
  ) completed_reports;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_clinician_imaging_results(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_clinician_imaging_results(integer) TO authenticated;

-- Keep report-view permission separate from department-workspace permission.
INSERT INTO public.permissions(permission_key, description, is_active)
VALUES
  ('laboratory_results', 'View approved laboratory reports for authorised patient/facility context', true),
  ('radiology_results', 'View completed radiology reports for authorised patient/facility context', true)
ON CONFLICT (permission_key) DO UPDATE
SET description = EXCLUDED.description, is_active = true, updated_at = now();

DELETE FROM public.role_permissions
WHERE role = 'practitioner' AND permission_key IN ('laboratory', 'radiology');

INSERT INTO public.role_permissions(role, permission_key)
VALUES
  ('admin', 'laboratory_results'),
  ('practitioner', 'laboratory_results'),
  ('practitioner', 'radiology_results'),
  ('nurse', 'laboratory_results'),
  ('nurse', 'radiology_results'),
  ('midwife', 'laboratory_results'),
  ('midwife', 'radiology_results'),
  ('specialist_nurse', 'laboratory_results'),
  ('specialist_nurse', 'radiology_results')
ON CONFLICT DO NOTHING;

COMMIT;
