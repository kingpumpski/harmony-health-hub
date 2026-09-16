-- Next-generation transfusion verification boundary.
-- A transfusion may be scheduled/issued first, but administration cannot begin
-- until compatibility and an independent witness are recorded server-side.

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

  IF NEW.status IN ('running','completed','stopped') AND NEW.compatibility_checked IS NOT TRUE THEN
    RAISE EXCEPTION 'Blood compatibility must be independently verified before transfusion can run';
  END IF;

  IF NEW.status IN ('running','completed','stopped') AND NEW.witnessed_by IS NULL THEN
    RAISE EXCEPTION 'An independent transfusion witness is required before administration';
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

CREATE OR REPLACE FUNCTION public.verify_transfusion_record(
  _record_id UUID,
  _witnessed_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  uid UUID := auth.uid();
  r public.transfusion_records%ROWTYPE;
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
  IF _witnessed_by IS NULL THEN RAISE EXCEPTION 'Independent witness is required'; END IF;
  IF _witnessed_by = uid THEN RAISE EXCEPTION 'The administering actor cannot self-witness a transfusion'; END IF;
  IF NOT (
    public.has_role(_witnessed_by,'admin') OR
    public.has_role(_witnessed_by,'practitioner') OR
    public.has_role(_witnessed_by,'nurse') OR
    public.has_role(_witnessed_by,'midwife') OR
    public.has_role(_witnessed_by,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Witness must hold an authorized clinical role';
  END IF;

  SELECT * INTO r FROM public.transfusion_records WHERE id=_record_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfusion record not found'; END IF;
  IF r.status <> 'issued' THEN
    RAISE EXCEPTION 'Only an issued transfusion can be independently verified';
  END IF;
  IF r.consent_confirmed IS NOT TRUE THEN RAISE EXCEPTION 'Documented transfusion consent is required'; END IF;
  IF NULLIF(trim(COALESCE(r.unit_identifier,'')),'') IS NULL THEN RAISE EXCEPTION 'Blood-unit identifier is required'; END IF;

  UPDATE public.transfusion_records
  SET compatibility_checked=true,
      witnessed_by=_witnessed_by,
      updated_at=now()
  WHERE id=_record_id;

  PERFORM public.record_system_audit(
    'transfusion_verified',
    'clinical',
    'transfusion_records',
    _record_id,
    'critical',
    jsonb_build_object('record_id',_record_id,'patient_id',r.patient_id,'verified_by',uid,'witnessed_by',_witnessed_by,'timestamp',now())
  );

  RETURN jsonb_build_object('record_id',_record_id,'compatibility_checked',true,'witnessed_by',_witnessed_by);
END;
$$;

REVOKE ALL ON FUNCTION public.verify_transfusion_record(UUID,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.verify_transfusion_record(UUID,UUID) TO authenticated;

COMMENT ON FUNCTION public.verify_transfusion_record(UUID,UUID) IS 'Server-authoritative independent transfusion verification; compatibility and witness are required before administration.';
