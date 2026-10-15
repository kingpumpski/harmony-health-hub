BEGIN;

ALTER TABLE public.lab_test_catalogue
  ADD COLUMN IF NOT EXISTS sample_quantity text;

-- Reconcile installations where sample_quantity was provisioned as numeric.
-- The canonical catalogue API represents this optional quantity as text.
DO $sample_quantity_type$
DECLARE
  v_type text;
BEGIN
  SELECT data_type INTO v_type
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'lab_test_catalogue'
    AND column_name = 'sample_quantity';

  IF v_type IS DISTINCT FROM 'text' THEN
    ALTER TABLE public.lab_test_catalogue
      ALTER COLUMN sample_quantity TYPE text
      USING sample_quantity::text;
  END IF;
END;
$sample_quantity_type$;

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
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility to access the laboratory workspace'; END IF;

  SELECT NULLIF(lower(trim(p.department)), '') INTO v_department
  FROM public.profiles p WHERE p.id = v_uid;

  IF NOT (
    public.has_role(v_uid, 'admin')
    OR public.has_role(v_uid, 'it_admin')
    OR (public.has_role(v_uid, 'lab_technician') AND (v_department IS NULL OR v_department = 'laboratory'))
    OR public.has_role(v_uid, 'practitioner')
    OR (public.has_role(v_uid, 'nurse') AND (v_department IS NULL OR v_department IN ('laboratory','clinical')))
    OR (public.has_role(v_uid, 'midwife') AND (v_department IS NULL OR v_department IN ('laboratory','clinical')))
    OR (public.has_role(v_uid, 'specialist_nurse') AND (v_department IS NULL OR v_department IN ('laboratory','clinical')))
    OR (public.has_role(v_uid, 'radiologist') AND (v_department IS NULL OR v_department = 'radiology'))
  ) THEN RAISE EXCEPTION 'Laboratory workspace access is not permitted'; END IF;

  _limit := LEAST(GREATEST(COALESCE(_limit, 200), 1), 500);

  SELECT jsonb_build_object(
    'patients', COALESCE((
      SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name, p.last_name)
      FROM (
        SELECT id, first_name, last_name, patient_code, email, gender, date_of_birth
        FROM public.patients
        WHERE COALESCE(status, 'active') <> 'inactive' AND facility_id = v_facility
        ORDER BY first_name, last_name LIMIT _limit
      ) p
    ), '[]'::jsonb),
    'catalogue', COALESCE((
      SELECT jsonb_agg(to_jsonb(c) ORDER BY c.test_name)
      FROM (
        SELECT id, test_code, test_name, category, specimen_type, sample_quantity, unit, reference_low,
               reference_high, reference_text, default_charge, active, parameters
        FROM public.lab_test_catalogue WHERE active
        ORDER BY test_name LIMIT _limit
      ) c
    ), '[]'::jsonb),
    'orders', COALESCE((
      SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC)
      FROM (
        SELECT lo.id, lo.patient_id, lo.test_name, lo.test_category, lo.priority,
               lo.status, lo.created_at, lo.clinical_notes, lo.lab_test_catalogue_id,
               lo.encounter_id, lo.facility_id, so.id AS service_order_id, so.status AS billing_status
        FROM public.lab_orders lo
        JOIN public.patients p ON p.id = lo.patient_id AND p.facility_id = v_facility
        JOIN LATERAL (
          SELECT s.id, s.status
          FROM public.service_orders s
          WHERE s.related_entity_id = lo.id
            AND s.department = 'laboratory'
            AND s.patient_id = lo.patient_id
            AND s.facility_id = lo.facility_id
            AND s.status IN ('released', 'in_progress', 'completed')
          ORDER BY s.created_at DESC
          LIMIT 1
        ) so ON true
        WHERE lo.facility_id = v_facility
        ORDER BY lo.created_at DESC LIMIT _limit
      ) o
    ), '[]'::jsonb),
    'results', COALESCE((
      SELECT jsonb_agg(to_jsonb(r) ORDER BY r.entered_at DESC)
      FROM (
        SELECT lr.id, lr.lab_order_id, lr.result_data, lr.parameter_results,
               lr.interpretation, lr.is_abnormal, lr.status, lr.entered_at,
               lr.approved_at, lr.approved_by, lr.numeric_value, lr.unit,
               lr.reference_low, lr.reference_high, lr.abnormal_flag, lr.patient_id
        FROM public.lab_results lr
        JOIN public.lab_orders lo ON lo.id = lr.lab_order_id
          AND lo.facility_id = v_facility AND lo.patient_id = lr.patient_id
        JOIN public.service_orders so ON so.related_entity_id = lo.id
          AND so.department = 'laboratory' AND so.patient_id = lo.patient_id
          AND so.facility_id = lo.facility_id
          AND so.status IN ('released', 'in_progress', 'completed')
        JOIN public.patients p ON p.id = lo.patient_id AND p.facility_id = v_facility
        WHERE lr.facility_id = v_facility
        ORDER BY lr.entered_at DESC LIMIT _limit
      ) r
    ), '[]'::jsonb)
  ) INTO result;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_laboratory_workspace(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_workspace(integer) TO authenticated;

CREATE TABLE IF NOT EXISTS public.lab_result_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_order_id uuid NOT NULL REFERENCES public.lab_orders(id) ON DELETE CASCADE,
  lab_result_id uuid REFERENCES public.lab_results(id) ON DELETE SET NULL,
  facility_id uuid NOT NULL,
  storage_path text NOT NULL UNIQUE,
  file_name text NOT NULL,
  mime_type text NOT NULL CHECK (mime_type IN ('application/pdf','image/jpeg','image/png')),
  file_size_bytes bigint NOT NULL CHECK (file_size_bytes BETWEEN 1 AND 15728640),
  uploaded_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.lab_result_attachments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lab_result_attachments FROM PUBLIC, anon;
GRANT SELECT, INSERT ON TABLE public.lab_result_attachments TO authenticated;
DROP POLICY IF EXISTS lab_result_attachments_facility_read ON public.lab_result_attachments;
CREATE POLICY lab_result_attachments_facility_read
  ON public.lab_result_attachments FOR SELECT TO authenticated
  USING (
    facility_id = (SELECT public.current_user_facility_id())
    AND (SELECT public.current_user_is_clinical_staff())
  );
DROP POLICY IF EXISTS lab_result_attachments_technician_insert ON public.lab_result_attachments;
CREATE POLICY lab_result_attachments_technician_insert
  ON public.lab_result_attachments FOR INSERT TO authenticated
  WITH CHECK (
    facility_id = (SELECT public.current_user_facility_id())
    AND uploaded_by = auth.uid()
    AND (
      (SELECT public.current_user_has_role('admin'::public.app_role))
      OR (SELECT public.current_user_has_role('it_admin'::public.app_role))
      OR (SELECT public.current_user_has_role('lab_technician'::public.app_role))
    )
    AND EXISTS (
      SELECT 1 FROM public.lab_orders lo
      JOIN public.service_orders so ON so.related_entity_id = lo.id
        AND so.department = 'laboratory'
        AND so.status IN ('released','in_progress','completed')
      WHERE lo.id = lab_result_attachments.lab_order_id
        AND lo.facility_id = lab_result_attachments.facility_id
    )
  );

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('lab-result-attachments', 'lab-result-attachments', false, 15728640,
        ARRAY['application/pdf','image/jpeg','image/png'])
ON CONFLICT (id) DO UPDATE
SET public = false, file_size_limit = 15728640,
    allowed_mime_types = ARRAY['application/pdf','image/jpeg','image/png'];

DROP POLICY IF EXISTS lab_result_attachments_storage_read ON storage.objects;
CREATE POLICY lab_result_attachments_storage_read
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'lab-result-attachments'
    AND EXISTS (
      SELECT 1 FROM public.lab_orders lo
      WHERE lo.id::text = split_part(name, '/', 1)
        AND lo.facility_id = (SELECT public.current_user_facility_id())
        AND (SELECT public.current_user_is_clinical_staff())
    )
  );
DROP POLICY IF EXISTS lab_result_attachments_storage_insert ON storage.objects;
CREATE POLICY lab_result_attachments_storage_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'lab-result-attachments'
    AND (
      (SELECT public.current_user_has_role('admin'::public.app_role))
      OR (SELECT public.current_user_has_role('it_admin'::public.app_role))
      OR (SELECT public.current_user_has_role('lab_technician'::public.app_role))
    )
    AND EXISTS (
      SELECT 1 FROM public.lab_orders lo
      JOIN public.service_orders so ON so.related_entity_id = lo.id
        AND so.department = 'laboratory'
        AND so.status IN ('released','in_progress','completed')
      WHERE lo.id::text = split_part(name, '/', 1)
        AND lo.facility_id = (SELECT public.current_user_facility_id())
    )
  );

CREATE OR REPLACE FUNCTION public.create_lab_test_catalogue_item_with_parameters(
  _test_code text,
  _test_name text,
  _category text,
  _specimen_type text,
  _unit text,
  _reference_low numeric,
  _reference_high numeric,
  _reference_text text,
  _default_charge numeric,
  _turnaround_minutes integer,
  _parameters jsonb DEFAULT '[]'::jsonb
)
RETURNS public.lab_test_catalogue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  r public.lab_test_catalogue;
  v_uid uuid := auth.uid();
  v_parameter jsonb;
  v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.current_user_has_catalogue_create_permission('create_items')
    OR public.current_user_has_catalogue_create_permission('create_services')
    OR public.has_role(v_uid,'admin')
    OR public.has_role(v_uid,'it_admin')
    OR public.has_role(v_uid,'lab_technician')
  ) THEN RAISE EXCEPTION 'Laboratory catalogue privilege required'; END IF;
  IF length(trim(coalesce(_test_code,''))) < 2 OR length(trim(coalesce(_test_name,''))) < 2 THEN
    RAISE EXCEPTION 'Test code and test name are required';
  END IF;
  IF coalesce(_default_charge,0) < 0 OR coalesce(_turnaround_minutes,0) < 0 THEN
    RAISE EXCEPTION 'Charge and turnaround time cannot be negative';
  END IF;
  IF _reference_low IS NOT NULL AND _reference_high IS NOT NULL AND _reference_low > _reference_high THEN
    RAISE EXCEPTION 'Reference low cannot exceed reference high';
  END IF;
  IF jsonb_typeof(coalesce(_parameters,'[]'::jsonb)) <> 'array'
     OR jsonb_array_length(coalesce(_parameters,'[]'::jsonb)) > 100 THEN
    RAISE EXCEPTION 'Laboratory parameters must be an array of at most 100 entries';
  END IF;
  FOR v_parameter IN SELECT value FROM jsonb_array_elements(coalesce(_parameters,'[]'::jsonb)) AS items(value)
  LOOP
    v_code := nullif(btrim(v_parameter->>'code'),'');
    IF jsonb_typeof(v_parameter) <> 'object' OR v_code IS NULL THEN
      RAISE EXCEPTION 'Each laboratory parameter must include a code';
    END IF;
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements(coalesce(_parameters,'[]'::jsonb)) AS items(value)
      WHERE nullif(btrim(value->>'code'),'') = v_code
      GROUP BY nullif(btrim(value->>'code'),'') HAVING count(*) > 1
    ) THEN RAISE EXCEPTION 'Laboratory parameter codes must be unique: %', v_code; END IF;
    IF coalesce(v_parameter->>'type','text') NOT IN ('text','numeric','number','boolean','select') THEN
      RAISE EXCEPTION 'Unsupported laboratory parameter type for %', v_code;
    END IF;
    IF v_parameter ? 'required' AND jsonb_typeof(v_parameter->'required') <> 'boolean' THEN
      RAISE EXCEPTION 'Parameter required must be boolean for %', v_code;
    END IF;
    IF v_parameter->>'reference_low' IS NOT NULL AND v_parameter->>'reference_high' IS NOT NULL
       AND (v_parameter->>'reference_low')::numeric > (v_parameter->>'reference_high')::numeric THEN
      RAISE EXCEPTION 'Parameter reference low cannot exceed high for %', v_code;
    END IF;
  END LOOP;

  INSERT INTO public.lab_test_catalogue(
    test_code,test_name,category,specimen_type,unit,reference_low,reference_high,
    reference_text,default_charge,turnaround_minutes,active,parameters
  ) VALUES (
    upper(btrim(_test_code)),btrim(_test_name),nullif(btrim(coalesce(_category,'')),''),
    nullif(btrim(coalesce(_specimen_type,'')),''),nullif(btrim(coalesce(_unit,'')),''),_reference_low,
    _reference_high,nullif(btrim(coalesce(_reference_text,'')),''),coalesce(_default_charge,0),
    coalesce(_turnaround_minutes,0),true,coalesce(_parameters,'[]'::jsonb)
  ) RETURNING * INTO r;

  PERFORM public.record_system_audit(
    'lab_test_catalogue_created','laboratory','lab_test_catalogue',r.id,'info',
    jsonb_build_object('test_code',r.test_code,'test_name',r.test_name,'parameter_count',jsonb_array_length(coalesce(r.parameters,'[]'::jsonb)))
  );
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_lab_test_catalogue_item_with_parameters(text,text,text,text,text,numeric,numeric,text,numeric,integer,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_lab_test_catalogue_item_with_parameters(text,text,text,text,text,numeric,numeric,text,numeric,integer,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_lab_test_catalogue_item_with_sample_quantity(
  _test_code text,
  _test_name text,
  _category text,
  _specimen_type text,
  _sample_quantity text,
  _unit text,
  _reference_low numeric,
  _reference_high numeric,
  _reference_text text,
  _default_charge numeric,
  _turnaround_minutes integer,
  _parameters jsonb DEFAULT '[]'::jsonb
)
RETURNS public.lab_test_catalogue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  r public.lab_test_catalogue;
BEGIN
  r := public.create_lab_test_catalogue_item_with_parameters(
    _test_code,_test_name,_category,_specimen_type,_unit,_reference_low,
    _reference_high,_reference_text,_default_charge,_turnaround_minutes,_parameters
  );
  UPDATE public.lab_test_catalogue
  SET sample_quantity = nullif(btrim(coalesce(_sample_quantity,'')), '')
  WHERE id = r.id
  RETURNING * INTO r;
  PERFORM public.record_system_audit(
    'lab_test_catalogue_sample_quantity_set','laboratory','lab_test_catalogue',
    r.id,'info',jsonb_build_object('test_code',r.test_code,'sample_quantity',r.sample_quantity)
  );
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_lab_test_catalogue_item_with_sample_quantity(text,text,text,text,text,text,numeric,numeric,text,numeric,integer,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_lab_test_catalogue_item_with_sample_quantity(text,text,text,text,text,text,numeric,numeric,text,numeric,integer,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_lab_result_draft(
  _lab_order_id uuid,
  _parameter_results jsonb,
  _result_text text DEFAULT NULL,
  _interpretation text DEFAULT NULL,
  _is_abnormal boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  o public.lab_orders%ROWTYPE;
  r public.lab_results%ROWTYPE;
  v_result_id uuid;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'lab_technician')
  ) THEN RAISE EXCEPTION 'Laboratory technician role required'; END IF;
  IF jsonb_typeof(COALESCE(_parameter_results, '{}'::jsonb)) <> 'object' THEN
    RAISE EXCEPTION 'Structured laboratory results must be a JSON object';
  END IF;
  SELECT * INTO o FROM public.lab_orders WHERE id = _lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  IF o.facility_id IS NULL OR o.facility_id IS DISTINCT FROM v_facility THEN
    RAISE EXCEPTION 'Laboratory order belongs to a different facility context';
  END IF;
  IF o.status <> 'sample_collected' THEN RAISE EXCEPTION 'Sample must be collected before result entry'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.service_orders so
    WHERE so.related_entity_id = o.id AND so.department = 'laboratory'
      AND so.patient_id = o.patient_id AND so.facility_id = o.facility_id
      AND so.status IN ('released','in_progress','completed')
  ) THEN RAISE EXCEPTION 'Billing release is required before result entry'; END IF;

  SELECT * INTO r FROM public.lab_results
  WHERE lab_order_id = o.id AND status = 'draft'
  ORDER BY entered_at DESC LIMIT 1 FOR UPDATE;
  IF FOUND THEN
    UPDATE public.lab_results SET
      result_data = jsonb_build_object('value', COALESCE(NULLIF(btrim(_result_text),''), _parameter_results::text)),
      parameter_results = COALESCE(_parameter_results, '{}'::jsonb),
      interpretation = NULLIF(btrim(_interpretation),''),
      is_abnormal = COALESCE(_is_abnormal,false),
      result = NULLIF(btrim(_result_text),''),
      updated_at = now()
    WHERE id = r.id RETURNING id INTO v_result_id;
  ELSE
    INSERT INTO public.lab_results(
      lab_order_id, patient_id, facility_id, result_data, parameter_results,
      interpretation, is_abnormal, entered_by, status, result
    ) VALUES (
      o.id, o.patient_id, o.facility_id,
      jsonb_build_object('value', COALESCE(NULLIF(btrim(_result_text),''), _parameter_results::text)),
      COALESCE(_parameter_results, '{}'::jsonb), NULLIF(btrim(_interpretation),''),
      COALESCE(_is_abnormal,false), uid, 'draft', NULLIF(btrim(_result_text),'')
    ) RETURNING id INTO v_result_id;
  END IF;
  RETURN v_result_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.save_lab_result_draft(uuid,jsonb,text,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_lab_result_draft(uuid,jsonb,text,text,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_lab_test_catalogue_charge(
  _catalogue_id uuid,
  _default_charge numeric
)
RETURNS public.lab_test_catalogue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  item public.lab_test_catalogue%ROWTYPE;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'lab_technician')
  ) THEN RAISE EXCEPTION 'Laboratory catalogue access required'; END IF;
  IF _default_charge IS NULL OR _default_charge < 0 THEN
    RAISE EXCEPTION 'Tariff must be a non-negative amount';
  END IF;
  UPDATE public.lab_test_catalogue
  SET default_charge = _default_charge, updated_at = now()
  WHERE id = _catalogue_id
  RETURNING * INTO item;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory catalogue item not found'; END IF;
  PERFORM public.record_system_audit(
    'lab_test_catalogue_tariff_updated','laboratory','lab_test_catalogue',
    item.id,'info',jsonb_build_object('test_code',item.test_code,'default_charge',item.default_charge)
  );
  RETURN item;
END;
$function$;

REVOKE ALL ON FUNCTION public.update_lab_test_catalogue_charge(uuid,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lab_test_catalogue_charge(uuid,numeric) TO authenticated;

COMMIT;
