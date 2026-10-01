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
        FROM public.lab_orders o
        WHERE o.status <> 'cancelled'
          AND NOT EXISTS (
            SELECT 1 FROM public.service_orders so
            WHERE so.related_entity_id = o.id
              AND so.order_type = 'lab'
              AND so.status = 'pending_payment_approval'
          )
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
SET search_path = ''
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
        WHERE io.status IN ('released', 'in_progress', 'completed')
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
        'result_text', r.result_data ->> 'value',
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


-- Only the imaging team can claim acquisition work. Clinicians can order studies
-- and review completed reports, but cannot move department work through its queue.
CREATE OR REPLACE FUNCTION public.start_imaging_order(_imaging_order_id uuid)
RETURNS public.imaging_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $
DECLARE
  uid uuid := auth.uid();
  o public.imaging_orders;
  s public.service_orders;
  es text;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'radiologist')
    OR public.has_role(uid, 'radiology_technician')
  ) THEN
    RAISE EXCEPTION 'Radiology operational role required';
  END IF;

  SELECT * INTO o FROM public.imaging_orders WHERE id = _imaging_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Imaging order not found'; END IF;
  IF o.status <> 'released' THEN RAISE EXCEPTION 'Imaging order must be released before it can start'; END IF;

  IF o.encounter_id IS NOT NULL THEN
    SELECT status INTO es FROM public.encounters WHERE id = o.encounter_id;
    IF es IN ('completed', 'cancelled') THEN
      RAISE EXCEPTION 'Cannot start imaging for a closed encounter';
    END IF;
  END IF;

  IF o.service_order_id IS NULL THEN
    UPDATE public.imaging_orders
    SET status = 'in_progress', performed_by = uid, updated_at = now()
    WHERE id = o.id
    RETURNING * INTO o;
    RETURN o;
  END IF;

  SELECT * INTO s FROM public.service_orders WHERE id = o.service_order_id FOR UPDATE;
  IF NOT FOUND OR s.patient_id <> o.patient_id OR s.related_entity_id <> o.id OR s.department <> 'imaging' THEN
    RAISE EXCEPTION 'Imaging service order linkage is invalid';
  END IF;
  IF s.status <> 'released' THEN RAISE EXCEPTION 'Linked service order must be released before imaging can start'; END IF;

  UPDATE public.service_orders
  SET status = 'in_progress', started_at = COALESCE(started_at, now()), updated_at = now()
  WHERE id = s.id;

  UPDATE public.department_queues
  SET status = 'claimed', claimed_by = uid, assigned_to = uid,
      claimed_at = COALESCE(claimed_at, now()), updated_at = now()
  WHERE service_order_id = s.id;

  UPDATE public.imaging_orders
  SET status = 'in_progress', performed_by = uid, updated_at = now()
  WHERE id = o.id
  RETURNING * INTO o;

  RETURN o;
END;
$;

REVOKE ALL ON FUNCTION public.start_imaging_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_imaging_order(uuid) TO authenticated;

-- Report completion/approval belongs to the radiologist (or administrator), not
-- the ordering clinician or acquisition technician.
CREATE OR REPLACE FUNCTION public.complete_imaging_order(
  _imaging_order_id uuid,
  _report text,
  _impression text
)
RETURNS public.imaging_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $
DECLARE
  uid uuid := auth.uid();
  o public.imaging_orders;
  s public.service_orders;
  es text;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'radiologist')
  ) THEN
    RAISE EXCEPTION 'Radiologist approval role required';
  END IF;
  IF NULLIF(btrim(COALESCE(_report, '')), '') IS NULL
     AND NULLIF(btrim(COALESCE(_impression, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A report or impression is required before completion';
  END IF;

  SELECT * INTO o FROM public.imaging_orders WHERE id = _imaging_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Imaging order not found'; END IF;
  IF o.status <> 'in_progress' THEN RAISE EXCEPTION 'Imaging order must be in progress before completion'; END IF;

  IF o.encounter_id IS NOT NULL THEN
    SELECT status INTO es FROM public.encounters WHERE id = o.encounter_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
    IF es IN ('completed', 'cancelled') THEN
      RAISE EXCEPTION 'Cannot complete imaging for a completed or cancelled encounter';
    END IF;
  END IF;

  IF o.service_order_id IS NOT NULL THEN
    SELECT * INTO s FROM public.service_orders WHERE id = o.service_order_id FOR UPDATE;
    IF NOT FOUND OR s.patient_id <> o.patient_id OR s.related_entity_id <> o.id OR s.department <> 'imaging' THEN
      RAISE EXCEPTION 'Imaging service order linkage is invalid';
    END IF;
    IF s.status <> 'in_progress' THEN RAISE EXCEPTION 'Linked service order must be in progress before imaging completion'; END IF;

    UPDATE public.service_orders SET status = 'completed', completed_at = now(), updated_at = now() WHERE id = s.id;
    UPDATE public.department_queues SET status = 'completed', completed_at = now(), updated_at = now() WHERE service_order_id = s.id;
  END IF;

  UPDATE public.imaging_orders
  SET report = NULLIF(btrim(COALESCE(_report, '')), ''),
      impression = NULLIF(btrim(COALESCE(_impression, '')), ''),
      status = 'completed',
      updated_at = now()
  WHERE id = o.id
  RETURNING * INTO o;

  IF o.requested_by IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE recipient_user_id = o.requested_by
      AND related_entity_id = o.id
      AND category = 'other'
      AND title = 'Radiology report ready'
  ) THEN
    INSERT INTO public.notifications(
      recipient_user_id, title, message, severity, category, link,
      related_patient_id, related_entity_id, metadata
    ) VALUES (
      o.requested_by,
      'Radiology report ready',
      format('The %s report for this patient is complete and ready for clinical review.', o.study_name),
      CASE WHEN lower(COALESCE(o.priority, 'routine')) IN ('urgent', 'stat') THEN 'warning' ELSE 'info' END,
      'other',
      '/clinical-results',
      o.patient_id,
      o.id,
      jsonb_build_object(
        'workflow', 'imaging_result_review',
        'imaging_order_id', o.id,
        'encounter_id', o.encounter_id,
        'service_order_id', o.service_order_id,
        'priority', o.priority
      )
    );
  END IF;

  RETURN o;
END;
$;

REVOKE ALL ON FUNCTION public.complete_imaging_order(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_imaging_order(uuid, text, text) TO authenticated;

-- Laboratory approval is reserved for the laboratory team and administrators.
-- The ordering clinician receives a notification linking to the report-only page.
CREATE OR REPLACE FUNCTION public.approve_lab_result(_lab_result_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $
DECLARE
  uid uuid := auth.uid();
  r public.lab_results%ROWTYPE;
  o public.lab_orders%ROWTYPE;
  encounter_patient_id uuid;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'lab_technician')
  ) THEN
    RAISE EXCEPTION 'Laboratory approval role required';
  END IF;

  SELECT * INTO r FROM public.lab_results WHERE id = _lab_result_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory result not found'; END IF;
  IF r.status <> 'completed' THEN RAISE EXCEPTION 'Only completed results can be approved'; END IF;

  SELECT * INTO o FROM public.lab_orders WHERE id = r.lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  IF o.status <> 'completed' THEN RAISE EXCEPTION 'Laboratory order must be completed before result approval'; END IF;

  IF r.patient_id IS NULL OR o.patient_id IS NULL OR r.patient_id IS DISTINCT FROM o.patient_id THEN
    RAISE EXCEPTION 'Laboratory result and order patient context do not match';
  END IF;

  IF o.encounter_id IS NOT NULL THEN
    SELECT e.patient_id INTO encounter_patient_id FROM public.encounters e WHERE e.id = o.encounter_id;
    IF encounter_patient_id IS NULL OR encounter_patient_id IS DISTINCT FROM o.patient_id THEN
      RAISE EXCEPTION 'Laboratory order encounter does not belong to patient';
    END IF;
  END IF;

  UPDATE public.lab_results
  SET status = 'approved', approved_by = uid, approved_at = now(), updated_at = now()
  WHERE id = r.id AND status = 'completed';

  UPDATE public.lab_orders
  SET status = 'approved', updated_at = now()
  WHERE id = o.id AND status = 'completed';

  IF o.ordered_by IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE recipient_user_id = o.ordered_by
      AND related_entity_id = o.id
      AND category = 'diagnostic_result'
      AND title = 'Laboratory result ready'
      AND is_read = false
  ) THEN
    INSERT INTO public.notifications(
      recipient_user_id, title, message, severity, category, link,
      related_patient_id, related_entity_id, metadata
    ) VALUES (
      o.ordered_by,
      'Laboratory result ready',
      format('The %s laboratory result is approved and ready for clinical review.', o.test_name),
      CASE WHEN COALESCE(r.is_abnormal, false) THEN 'critical' ELSE 'info' END,
      'diagnostic_result',
      '/lab-results',
      o.patient_id,
      o.id,
      jsonb_build_object(
        'workflow', 'lab_result_review',
        'lab_result_id', r.id,
        'lab_order_id', o.id,
        'encounter_id', o.encounter_id,
        'is_abnormal', COALESCE(r.is_abnormal, false),
        'requires_acknowledgement', true
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'lab_result_id', r.id,
    'lab_order_id', o.id,
    'encounter_id', o.encounter_id,
    'status', 'approved'
  );
END;
$;

REVOKE ALL ON FUNCTION public.approve_lab_result(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_lab_result(uuid) TO authenticated;

COMMIT;
