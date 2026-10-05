-- Corrective hardening: enforce patient/facility context on transfusion lifecycle updates.
-- The live function is recreated here because its existing parameter defaults prevented
-- CREATE OR REPLACE from removing the legacy defaults.

DROP FUNCTION IF EXISTS public.record_transfusion_event(uuid,text,boolean,text);

CREATE FUNCTION public.record_transfusion_event(
  _record_id uuid,
  _status text,
  _reaction_observed boolean,
  _reaction_notes text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  r public.transfusion_records%ROWTYPE;
  es text;
  allowed boolean := false;
  patient_facility uuid;
  active_facility uuid;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Clinical role required';
  END IF;

  IF _status NOT IN ('issued','running','completed','stopped','cancelled') THEN
    RAISE EXCEPTION 'Invalid transfusion status';
  END IF;

  SELECT * INTO r
  FROM public.transfusion_records
  WHERE id = _record_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfusion record not found';
  END IF;

  IF r.patient_id IS NULL THEN
    RAISE EXCEPTION 'Transfusion record patient attribution is unresolved';
  END IF;

  PERFORM public.assert_patient_facility_context(r.patient_id);

  SELECT facility_id INTO patient_facility
  FROM public.patients
  WHERE id = r.patient_id;

  IF patient_facility IS NULL THEN
    RAISE EXCEPTION 'Patient facility attribution is unresolved';
  END IF;

  IF r.facility_id IS NOT NULL
     AND r.facility_id IS DISTINCT FROM patient_facility THEN
    RAISE EXCEPTION 'Transfusion record facility does not match patient facility';
  END IF;

  active_facility := public.current_user_facility_id();

  IF NOT public.has_role(uid,'admin')
     AND (active_facility IS NULL OR active_facility IS DISTINCT FROM patient_facility) THEN
    RAISE EXCEPTION 'Transfusion record belongs to a different facility context';
  END IF;

  IF r.status IN ('completed','stopped','cancelled') AND _status <> r.status THEN
    RAISE EXCEPTION 'Closed transfusion record cannot be reopened';
  END IF;

  IF r.status = 'issued' AND _status IN ('running','cancelled') THEN
    allowed := true;
  ELSIF r.status = 'running' AND _status IN ('completed','stopped','cancelled') THEN
    allowed := true;
  ELSIF _status = r.status THEN
    allowed := true;
  END IF;

  IF NOT allowed THEN
    RAISE EXCEPTION 'Invalid transfusion lifecycle transition';
  END IF;

  IF r.encounter_id IS NOT NULL THEN
    SELECT status INTO es
    FROM public.encounters
    WHERE id = r.encounter_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Linked encounter not found';
    END IF;

    IF es = 'cancelled'
       OR (es = 'completed' AND _status NOT IN ('completed','stopped','cancelled')) THEN
      RAISE EXCEPTION 'Cannot change transfusion lifecycle for a closed encounter';
    END IF;
  END IF;

  IF _status IN ('running','completed') AND r.compatibility_checked IS NOT TRUE THEN
    RAISE EXCEPTION 'Transfusion must be independently verified before administration';
  END IF;

  UPDATE public.transfusion_records
  SET status = _status,
      reaction_observed = COALESCE(_reaction_observed,false),
      reaction_notes = CASE
        WHEN COALESCE(_reaction_observed,false)
          THEN NULLIF(pg_catalog.btrim(_reaction_notes),'')
        ELSE reaction_notes
      END,
      started_at = CASE
        WHEN _status = 'running' AND started_at IS NULL THEN pg_catalog.now()
        ELSE started_at
      END,
      completed_at = CASE
        WHEN _status IN ('completed','stopped') THEN COALESCE(completed_at,pg_catalog.now())
        ELSE completed_at
      END,
      administered_by = COALESCE(administered_by,uid),
      updated_at = pg_catalog.now(),
      facility_id = COALESCE(facility_id,patient_facility)
  WHERE id = r.id;

  PERFORM public.record_system_audit(
    'transfusion_event_recorded',
    'transfusion',
    'transfusion_records',
    r.id,
    'info',
    jsonb_build_object(
      'patient_id',r.patient_id,
      'facility_id',patient_facility,
      'status',_status
    )
  );

  RETURN jsonb_build_object(
    'record_id',r.id,
    'status',_status,
    'reaction_observed',COALESCE(_reaction_observed,false)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) TO authenticated;
