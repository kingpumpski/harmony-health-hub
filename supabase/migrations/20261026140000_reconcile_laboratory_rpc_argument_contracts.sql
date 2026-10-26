BEGIN;

-- Align the live laboratory panel and attachment RPC signatures with the deployed client.
-- Existing production tables predate the newer panel contract; reconcile additively.
ALTER TABLE public.lab_test_groups
  ADD COLUMN IF NOT EXISTS facility_id uuid REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS group_code text,
  ADD COLUMN IF NOT EXISTS default_charge numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id);

ALTER TABLE public.lab_test_group_items
  ADD COLUMN IF NOT EXISTS display_order integer,
  ADD COLUMN IF NOT EXISTS test_id uuid REFERENCES public.lab_test_catalogue(id) ON DELETE RESTRICT;

UPDATE public.lab_test_groups
SET group_code = upper(regexp_replace(name, '[^A-Za-z0-9]+', '-', 'g'))
WHERE group_code IS NULL OR btrim(group_code) = '';

UPDATE public.lab_test_group_items
SET display_order = COALESCE(sort_order, 0),
    test_id = COALESCE(test_id, test_catalogue_id)
WHERE display_order IS NULL OR test_id IS NULL;

CREATE INDEX IF NOT EXISTS lab_test_groups_facility_active_idx
  ON public.lab_test_groups(facility_id, is_active, name);
CREATE UNIQUE INDEX IF NOT EXISTS lab_test_groups_facility_code_uidx
  ON public.lab_test_groups(facility_id, lower(group_code))
  WHERE facility_id IS NOT NULL AND group_code IS NOT NULL;

DROP FUNCTION IF EXISTS public.get_laboratory_test_groups(boolean);
CREATE OR REPLACE FUNCTION public.get_laboratory_test_groups(_include_inactive boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  result jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility to access laboratory panels'; END IF;
  IF NOT (
    public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin')
    OR public.has_role(uid, 'lab_technician') OR public.has_role(uid, 'practitioner')
    OR public.has_role(uid, 'nurse') OR public.has_role(uid, 'midwife')
    OR public.has_role(uid, 'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Laboratory panel access is not permitted'; END IF;
  IF _include_inactive AND NOT (
    public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin')
    OR public.has_role(uid, 'lab_technician')
  ) THEN RAISE EXCEPTION 'Laboratory panel administration access is not permitted'; END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', g.id,
      'group_name', g.name,
      'group_code', g.group_code,
      'description', g.description,
      'default_charge', g.default_charge,
      'is_active', g.is_active,
      'tests', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', c.id,
          'test_code', c.test_code,
          'test_name', c.test_name,
          'category', c.category,
          'parameters', c.parameters,
          'active', c.active,
          'display_order', COALESCE(i.display_order, i.sort_order, 0)
        ) ORDER BY COALESCE(i.display_order, i.sort_order, 0))
        FROM public.lab_test_group_items i
        JOIN public.lab_test_catalogue c ON c.id = COALESCE(i.test_id, i.test_catalogue_id)
        WHERE i.lab_test_group_id = g.id
          AND (_include_inactive OR c.active)
      ), '[]'::jsonb)
    ) ORDER BY g.name
  ), '[]'::jsonb)
  INTO result
  FROM public.lab_test_groups g
  WHERE g.facility_id = v_facility
    AND (_include_inactive OR g.is_active);
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_laboratory_test_group(
  _group_id uuid,
  _group_name text,
  _group_code text,
  _description text,
  _default_charge numeric,
  _test_ids uuid[],
  _is_active boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_group_id uuid;
  v_test_id uuid;
  v_order integer := 0;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility to manage laboratory panels'; END IF;
  IF NOT (
    public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin')
    OR public.has_role(uid, 'lab_technician')
  ) THEN RAISE EXCEPTION 'Laboratory panel administration access is not permitted'; END IF;
  IF length(btrim(COALESCE(_group_name, ''))) NOT BETWEEN 2 AND 120
     OR length(btrim(COALESCE(_group_code, ''))) NOT BETWEEN 2 AND 40
     OR COALESCE(_default_charge, -1) < 0
     OR COALESCE(cardinality(_test_ids), 0) = 0 THEN
    RAISE EXCEPTION 'A valid panel name, code, non-negative tariff and at least one test are required';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(_test_ids) AS selected(id)
    LEFT JOIN public.lab_test_catalogue c ON c.id = selected.id
    WHERE c.id IS NULL OR NOT c.active
  ) THEN RAISE EXCEPTION 'Every panel test must exist and be active'; END IF;

  IF _group_id IS NULL THEN
    INSERT INTO public.lab_test_groups(name, description, facility_id, group_code, default_charge, is_active, created_by)
    VALUES (btrim(_group_name), NULLIF(btrim(COALESCE(_description, '')), ''), v_facility,
            upper(btrim(_group_code)), _default_charge, _is_active, uid)
    RETURNING id INTO v_group_id;
  ELSE
    UPDATE public.lab_test_groups
    SET name = btrim(_group_name),
        description = NULLIF(btrim(COALESCE(_description, '')), ''),
        group_code = upper(btrim(_group_code)),
        default_charge = _default_charge,
        is_active = _is_active,
        created_by = COALESCE(created_by, uid),
        updated_at = now()
    WHERE id = _group_id AND facility_id = v_facility
    RETURNING id INTO v_group_id;
    IF v_group_id IS NULL THEN RAISE EXCEPTION 'Panel not found in the active facility'; END IF;
    DELETE FROM public.lab_test_group_items WHERE lab_test_group_id = v_group_id;
  END IF;

  FOREACH v_test_id IN ARRAY _test_ids LOOP
    INSERT INTO public.lab_test_group_items(lab_test_group_id, test_catalogue_id, sort_order, required, display_order, test_id)
    VALUES (v_group_id, v_test_id, v_order, true, v_order, v_test_id);
    v_order := v_order + 1;
  END LOOP;
  RETURN jsonb_build_object('id', v_group_id, 'saved', true);
END;
$function$;

DROP FUNCTION IF EXISTS public.get_lab_result_attachments(uuid[]);
CREATE OR REPLACE FUNCTION public.get_lab_result_attachments(_lab_order_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  result jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility to access laboratory report attachments'; END IF;
  IF NOT (
    public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin')
    OR public.current_user_is_clinical_staff()
  ) THEN RAISE EXCEPTION 'Clinical staff or facility administrator access is required'; END IF;
  IF COALESCE(cardinality(_lab_order_ids), 0) > 300 THEN
    RAISE EXCEPTION 'A maximum of 300 laboratory orders may be requested at once';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'lab_order_id', a.lab_order_id,
    'storage_path', a.storage_path,
    'file_name', a.file_name,
    'mime_type', a.mime_type,
    'created_at', a.created_at
  ) ORDER BY a.created_at DESC), '[]'::jsonb)
  INTO result
  FROM (
    SELECT att.id, att.lab_order_id, att.storage_path, att.file_name, att.mime_type, att.created_at
    FROM public.lab_result_attachments att
    JOIN public.lab_orders lo ON lo.id = att.lab_order_id AND lo.facility_id = att.facility_id
    JOIN public.patients p ON p.id = lo.patient_id AND p.facility_id = lo.facility_id
    WHERE att.facility_id = v_facility
      AND att.lab_order_id = ANY(COALESCE(_lab_order_ids, ARRAY[]::uuid[]))
      AND att.storage_path IS NOT NULL AND btrim(att.storage_path) <> ''
      AND att.file_name IS NOT NULL AND att.mime_type IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.lab_result_attachments dup
        WHERE dup.storage_path = att.storage_path AND dup.id <> att.id
      )
      AND (
        att.lab_result_id IS NULL OR EXISTS (
          SELECT 1 FROM public.lab_results lr
          WHERE lr.id = att.lab_result_id AND lr.lab_order_id = lo.id
            AND lr.patient_id = lo.patient_id AND lr.facility_id = lo.facility_id
        )
      )
    ORDER BY att.created_at DESC
    LIMIT 1000
  ) a;
  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_laboratory_test_groups(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_test_groups(boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.save_laboratory_test_group(uuid,text,text,text,numeric,uuid[],boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_laboratory_test_group(uuid,text,text,text,numeric,uuid[],boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.get_lab_result_attachments(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_lab_result_attachments(uuid[]) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;