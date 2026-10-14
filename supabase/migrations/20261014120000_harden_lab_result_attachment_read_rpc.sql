BEGIN;

-- Harden the attachment read API without changing the existing table or storage policies.
-- Keep bulk requests bounded and verify order, patient, result, facility, and billing lineage.
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
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'Select an active facility to access laboratory report attachments';
  END IF;
  IF NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'it_admin')
    OR public.current_user_is_clinical_staff()
  ) THEN
    RAISE EXCEPTION 'Clinical staff or facility administrator access is required for laboratory report attachments';
  END IF;
  IF coalesce(cardinality(_lab_order_ids), 0) > 300 THEN
    RAISE EXCEPTION 'A maximum of 300 laboratory orders may be requested at once';
  END IF;

  SELECT coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', attachment.id,
        'lab_order_id', attachment.lab_order_id,
        'storage_path', attachment.storage_path,
        'file_name', attachment.file_name,
        'mime_type', attachment.mime_type,
        'created_at', attachment.created_at
      ) ORDER BY attachment.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO result
  FROM (
    SELECT a.id, a.lab_order_id, a.storage_path, a.file_name, a.mime_type, a.created_at
    FROM public.lab_result_attachments a
    JOIN public.lab_orders lo
      ON lo.id = a.lab_order_id
     AND lo.facility_id = a.facility_id
    JOIN public.patients p
      ON p.id = lo.patient_id
     AND p.facility_id = lo.facility_id
    WHERE a.facility_id = v_facility
      AND a.lab_order_id = ANY(coalesce(_lab_order_ids, ARRAY[]::uuid[]))
      AND EXISTS (
        SELECT 1
        FROM public.service_orders so
        WHERE so.related_entity_id = coalesce(lo.parent_order_id, lo.id)
          AND so.department = 'laboratory'
          AND so.patient_id = lo.patient_id
          AND so.facility_id = lo.facility_id
          AND so.status IN ('released', 'in_progress', 'completed')
      )
      AND (
        a.lab_result_id IS NULL
        OR EXISTS (
          SELECT 1
          FROM public.lab_results lr
          WHERE lr.id = a.lab_result_id
            AND lr.lab_order_id = lo.id
            AND lr.patient_id = lo.patient_id
            AND lr.facility_id = lo.facility_id
        )
      )
    ORDER BY a.created_at DESC
    LIMIT 1000
  ) attachment;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_lab_result_attachments(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_lab_result_attachments(uuid[]) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
