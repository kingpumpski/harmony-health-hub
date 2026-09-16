-- Next-generation transfusion safety boundary.
-- Reuses the existing transfusion_records lifecycle RPC and keeps direct authenticated DML revoked.

CREATE OR REPLACE FUNCTION public.guard_transfusion_record_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path=public
AS $$
BEGIN
  IF NEW.status IN ('issued','running','completed','stopped') AND NEW.consent_confirmed IS NOT TRUE THEN
    RAISE EXCEPTION 'Transfusion consent must remain confirmed for an active or completed transfusion';
  END IF;

  IF NEW.status IN ('running','completed','stopped') AND NULLIF(trim(COALESCE(NEW.unit_identifier,'')),'') IS NULL THEN
    RAISE EXCEPTION 'A blood-unit identifier is required before transfusion can run';
  END IF;

  IF NEW.reaction_observed IS TRUE AND NULLIF(trim(COALESCE(NEW.reaction_notes,'')),'') IS NULL THEN
    RAISE EXCEPTION 'A transfusion reaction requires clinical documentation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS t_transfusion_integrity_guard ON public.transfusion_records;
CREATE TRIGGER t_transfusion_integrity_guard
BEFORE INSERT OR UPDATE ON public.transfusion_records
FOR EACH ROW EXECUTE FUNCTION public.guard_transfusion_record_integrity();

CREATE OR REPLACE FUNCTION public.record_transfusion_event(
  _record_id uuid,
  _status text,
  _reaction_observed boolean DEFAULT false,
  _reaction_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  uid uuid := auth.uid();
  r public.transfusion_records%ROWTYPE;
  encounter_status text;
  reaction_notes_text text := NULLIF(trim(COALESCE(_reaction_notes,'')), '');
  allowed boolean := false;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR
    public.has_role(uid,'practitioner') OR
    public.has_role(uid,'nurse') OR
    public.has_role(uid,'midwife') OR
    public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Clinical role required';
  END IF;

  IF _status NOT IN ('issued','running','completed','stopped','cancelled') THEN
    RAISE EXCEPTION 'Invalid transfusion status';
  END IF;

  SELECT * INTO r FROM public.transfusion_records WHERE id=_record_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'Transfusion record not found'; END IF;

  IF r.status IN ('completed','stopped','cancelled') THEN
    IF _status=r.status THEN
      RETURN jsonb_build_object('record_id',r.id,'status',r.status,'idempotent',true);
    END IF;
    RAISE EXCEPTION 'Closed transfusion record cannot be reopened or changed';
  END IF;

  allowed := CASE r.status
    WHEN 'issued' THEN _status IN ('running','cancelled')
    WHEN 'running' THEN _status IN ('completed','stopped')
    ELSE false
  END;
  IF NOT allowed THEN
    RAISE EXCEPTION 'Invalid transfusion state transition from % to %',r.status,_status;
  END IF;

  IF r.encounter_id IS NOT NULL THEN
    SELECT status INTO encounter_status FROM public.encounters WHERE id=r.encounter_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
    IF encounter_status='cancelled' OR (encounter_status='completed' AND _status NOT IN ('completed','stopped','cancelled')) THEN
      RAISE EXCEPTION 'Cannot change transfusion lifecycle for a closed encounter';
    END IF;
  END IF;

  IF _status IN ('running','completed','stopped') AND r.consent_confirmed IS NOT TRUE THEN
    RAISE EXCEPTION 'Documented transfusion consent is required';
  END IF;
  IF _status IN ('running','completed','stopped') AND NULLIF(trim(COALESCE(r.unit_identifier,'')),'') IS NULL THEN
    RAISE EXCEPTION 'Blood-unit identifier is required before transfusion can run';
  END IF;
  IF _reaction_observed IS TRUE AND reaction_notes_text IS NULL THEN
    RAISE EXCEPTION 'Transfusion reaction requires clinical documentation';
  END IF;

  UPDATE public.transfusion_records
  SET status=_status,
      reaction_observed=COALESCE(_reaction_observed,false),
      reaction_notes=CASE WHEN _reaction_observed IS TRUE THEN reaction_notes_text ELSE reaction_notes END,
      started_at=CASE WHEN _status='running' AND started_at IS NULL THEN now() ELSE started_at END,
      completed_at=CASE WHEN _status IN ('completed','stopped') THEN COALESCE(completed_at,now()) ELSE completed_at END,
      administered_by=CASE WHEN _status IN ('running','completed','stopped') THEN COALESCE(administered_by,uid) ELSE administered_by END,
      updated_at=now()
  WHERE id=_record_id;

  PERFORM public.record_system_audit(
    'transfusion_'||_status,
    'clinical',
    'transfusion_records',
    _record_id,
    CASE WHEN _reaction_observed IS TRUE THEN 'critical' ELSE 'info' END,
    jsonb_build_object('record_id',_record_id,'patient_id',r.patient_id,'status',_status,'actor_id',uid,'reaction_observed',COALESCE(_reaction_observed,false),'reaction_notes',reaction_notes_text,'timestamp',now())
  );

  RETURN jsonb_build_object('record_id',_record_id,'status',_status,'reaction_observed',COALESCE(_reaction_observed,false),'idempotent',false);
END;
$$;

REVOKE ALL ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.transfusion_records FROM authenticated;
COMMENT ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) IS 'Server-authoritative transfusion lifecycle with row locking, monotonic state transitions, consent/unit/reaction controls and audit.';
