-- Durable, auditable acknowledgement for high-priority medication alerts.
-- Acknowledgement silences the alert; it never changes the medication administration status.

ALTER TABLE public.medication_administrations
  ADD COLUMN IF NOT EXISTS alert_acknowledged_at timestamptz,
  ADD COLUMN IF NOT EXISTS alert_acknowledged_by uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'medication_administrations_alert_acknowledged_by_fkey'
  ) THEN
    ALTER TABLE public.medication_administrations
      ADD CONSTRAINT medication_administrations_alert_acknowledged_by_fkey
      FOREIGN KEY (alert_acknowledged_by) REFERENCES auth.users(id);
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_medication_administrations_alert_ack
  ON public.medication_administrations (alert_acknowledged_at)
  WHERE status = 'scheduled' AND alert_acknowledged_at IS NULL;

CREATE OR REPLACE FUNCTION public.acknowledge_medication_alert(_record_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  uid uuid := auth.uid();
  r public.medication_administrations%ROWTYPE;
  v_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid, 'admin') OR public.has_role(uid, 'nurse') OR public.has_role(uid, 'specialist_nurse') OR public.has_role(uid, 'midwife')) THEN
    RAISE EXCEPTION 'Nursing clinical role required';
  END IF;

  SELECT * INTO r FROM public.medication_administrations WHERE id = _record_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Medication administration record not found'; END IF;

  v_facility := public.current_user_facility_id();
  IF r.facility_id IS NOT NULL AND v_facility IS NOT NULL
     AND r.facility_id IS DISTINCT FROM v_facility
     AND NOT public.has_role(uid, 'admin') THEN
    RAISE EXCEPTION 'Medication alert belongs to another facility';
  END IF;

  IF r.status <> 'scheduled' THEN
    RAISE EXCEPTION 'Only scheduled medication alerts can be acknowledged';
  END IF;

  UPDATE public.medication_administrations
  SET alert_acknowledged_at = COALESCE(alert_acknowledged_at, pg_catalog.now()),
      alert_acknowledged_by = COALESCE(alert_acknowledged_by, uid),
      updated_at = pg_catalog.now()
  WHERE id = _record_id
  RETURNING * INTO r;

  PERFORM public.record_system_audit(
    'medication_alert_acknowledged','clinical','medication_administrations',r.id,'info',
    jsonb_build_object('record_id',r.id,'patient_id',r.patient_id,'prescription_id',r.prescription_id,'acknowledged_by',uid,'acknowledged_at',r.alert_acknowledged_at)
  );

  RETURN jsonb_build_object('id',r.id,'status',r.status,'alert_acknowledged_at',r.alert_acknowledged_at,'alert_acknowledged_by',r.alert_acknowledged_by);
END;
$function$;

REVOKE ALL ON FUNCTION public.acknowledge_medication_alert(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.acknowledge_medication_alert(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_medication_alert(uuid) TO authenticated;
