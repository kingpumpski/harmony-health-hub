BEGIN;

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
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility to access laboratory attachments'; END IF;
  IF NOT (
    public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'lab_technician'::public.app_role) OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role) OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)
  ) THEN RAISE EXCEPTION 'Laboratory attachment access is not permitted'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.created_at DESC),'[]'::jsonb)
  INTO result
  FROM (
    SELECT attachment.id,attachment.lab_order_id,attachment.storage_path,
      attachment.file_name,attachment.mime_type,attachment.created_at
    FROM public.lab_result_attachments attachment
    JOIN public.lab_orders lo ON lo.id=attachment.lab_order_id
    JOIN public.patients p ON p.id=lo.patient_id AND p.facility_id=v_facility
    JOIN public.service_orders so ON so.related_entity_id=coalesce(lo.parent_order_id,lo.id)
      AND so.department='laboratory' AND so.patient_id=lo.patient_id
      AND so.facility_id=lo.facility_id AND so.status IN ('released','in_progress','completed')
    WHERE attachment.facility_id=v_facility
      AND lo.facility_id=v_facility
      AND attachment.lab_order_id=ANY(coalesce(_lab_order_ids,'{}'::uuid[]))
    ORDER BY attachment.created_at DESC
    LIMIT 1000
  ) a;
  RETURN result;
END;
$function$;

-- Keep the previously reported singular RPC spelling available to older
-- browser bundles while all current clients use the plural canonical name.
CREATE OR REPLACE FUNCTION public.get_laboratory_test_group(_include_inactive boolean DEFAULT false)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = ''
AS $function$
  SELECT public.get_laboratory_test_groups(_include_inactive);
$function$;

REVOKE ALL ON FUNCTION public.get_lab_result_attachments(uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_lab_result_attachments(uuid[]) TO authenticated;
REVOKE ALL ON FUNCTION public.get_laboratory_test_group(boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_test_group(boolean) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
