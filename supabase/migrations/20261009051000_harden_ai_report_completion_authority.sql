-- Keep AI report content completion on the trusted Edge Function path.
-- Patients may request reports and mark their own pending request as failed, but
-- must never be able to write the generated report content through the Data API.
BEGIN;

CREATE OR REPLACE FUNCTION public.complete_ai_report_request(
  _request_id uuid,
  _content text DEFAULT NULL,
  _error text DEFAULT NULL
)
RETURNS public.ai_report_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_request public.ai_report_requests;
  v_content text := NULLIF(pg_catalog.btrim(COALESCE(_content, '')), '');
  v_error text := NULLIF(pg_catalog.btrim(COALESCE(_error, '')), '');
BEGIN
  IF pg_catalog.current_setting('request.jwt.claim.role', true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'AI report completion is restricted to the trusted report service';
  END IF;

  SELECT * INTO v_request
  FROM public.ai_report_requests
  WHERE id = _request_id
  FOR UPDATE;

  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Report request not found';
  END IF;

  IF v_request.status IN ('completed', 'failed') THEN
    RETURN v_request;
  END IF;
  IF v_request.status <> 'processing' THEN
    RAISE EXCEPTION 'Report request is not processing';
  END IF;
  IF v_content IS NULL AND v_error IS NULL THEN
    RAISE EXCEPTION 'Report content or error is required';
  END IF;

  UPDATE public.ai_report_requests
  SET status = CASE WHEN v_content IS NOT NULL THEN 'completed' ELSE 'failed' END,
      content = CASE WHEN v_content IS NOT NULL THEN v_content ELSE NULL END,
      error = CASE WHEN v_content IS NULL THEN pg_catalog.left(v_error, 1000) ELSE NULL END,
      completed_at = pg_catalog.now()
  WHERE id = _request_id
  RETURNING * INTO v_request;

  RETURN v_request;
END;
$function$;

REVOKE ALL ON FUNCTION public.complete_ai_report_request(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_ai_report_request(uuid, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.fail_ai_report_request(
  _request_id uuid,
  _error text DEFAULT 'Report generation failed'
)
RETURNS public.ai_report_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_email text := pg_catalog.lower(NULLIF(pg_catalog.btrim(auth.jwt() ->> 'email'), ''));
  v_request public.ai_report_requests;
  v_owned boolean := false;
  v_error text := COALESCE(
    NULLIF(pg_catalog.btrim(_error), ''),
    'Report generation failed'
  );
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT * INTO v_request
  FROM public.ai_report_requests
  WHERE id = _request_id
  FOR UPDATE;

  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Report request not found';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.patients p
    WHERE p.id = v_request.patient_id
      AND (
        p.user_id = v_uid
        OR (p.user_id IS NULL AND v_email IS NOT NULL AND pg_catalog.lower(p.email) = v_email)
      )
  ) INTO v_owned;

  IF NOT (v_request.requested_by = v_uid AND v_owned) THEN
    RAISE EXCEPTION 'Not authorised to fail this patient report request';
  END IF;

  IF v_request.status IN ('completed', 'failed') THEN
    RETURN v_request;
  END IF;
  IF v_request.status <> 'processing' THEN
    RAISE EXCEPTION 'Report request is not processing';
  END IF;

  UPDATE public.ai_report_requests
  SET status = 'failed',
      content = NULL,
      error = pg_catalog.left(v_error, 1000),
      completed_at = pg_catalog.now()
  WHERE id = _request_id
  RETURNING * INTO v_request;

  RETURN v_request;
END;
$function$;

REVOKE ALL ON FUNCTION public.fail_ai_report_request(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fail_ai_report_request(uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
