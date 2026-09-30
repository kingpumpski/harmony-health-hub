-- Harden durable medication-alert acknowledgement for the Harmony clinical workflow.
-- Keep the acknowledgement idempotent, facility-scoped, auditable, and safe for SECURITY DEFINER execution.

CREATE OR REPLACE FUNCTION public.acknowledge_medication_alert(_record_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  r public.medication_administrations%ROWTYPE;
  v_facility uuid;
  v_existing_ack timestamptz;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'nurse')
    OR public.has_role(uid, 'specialist_nurse')
    OR public.has_role(uid, 'midwife')
  ) THEN
    RAISE EXCEPTION 'Nursing clinical role required';
  END IF;

  v_facility := public.current_user_facility_id();

  SELECT *
  INTO r
  FROM public.medication_administrations
  WHERE id = _record_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Medication administration record not found';
  END IF;

  -- Clinical medication records remain facility-scoped for every role,
  -- including platform administrators. Do not use administrative privilege
  -- as a cross-facility clinical access path.
  IF r.facility_id IS NULL OR v_facility IS NULL OR r.facility_id IS DISTINCT FROM v_facility THEN
    RAISE EXCEPTION 'Medication alert belongs to another facility';
  END IF;

  IF r.status <> 'scheduled' THEN
    RAISE EXCEPTION 'Only scheduled medication alerts can be acknowledged';
  END IF;

  v_existing_ack := r.alert_acknowledged_at;

  IF v_existing_ack IS NULL THEN
    UPDATE public.medication_administrations
    SET alert_acknowledged_at = pg_catalog.now(),
        alert_acknowledged_by = uid,
        updated_at = pg_catalog.now()
    WHERE id = _record_id
    RETURNING * INTO r;

    PERFORM public.record_system_audit(
      'medication_alert_acknowledged',
      'clinical',
      'medication_administrations',
      r.id,
      'info',
      jsonb_build_object(
        'record_id', r.id,
        'patient_id', r.patient_id,
        'prescription_id', r.prescription_id,
        'acknowledged_by', uid,
        'acknowledged_at', r.alert_acknowledged_at
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'id', r.id,
    'status', r.status,
    'alert_acknowledged_at', r.alert_acknowledged_at,
    'alert_acknowledged_by', r.alert_acknowledged_by,
    'already_acknowledged', v_existing_ack IS NOT NULL
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.acknowledge_medication_alert(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.acknowledge_medication_alert(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_medication_alert(uuid) TO authenticated;
