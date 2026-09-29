-- Prevent cross-facility ward-bed mutation through the SECURITY DEFINER status RPC.
CREATE OR REPLACE FUNCTION public.set_ward_bed_status(_bed_id uuid, _status text, _notes text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  uid UUID := auth.uid();
  v_bed public.ward_beds%ROWTYPE;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Nursing role required';
  END IF;

  IF _status NOT IN ('available','cleaning','maintenance','blocked','reserved') THEN
    RAISE EXCEPTION 'Unsupported bed status';
  END IF;

  SELECT *
    INTO v_bed
  FROM public.ward_beds
  WHERE id = _bed_id
  FOR UPDATE;

  IF v_bed.id IS NULL THEN
    RAISE EXCEPTION 'Bed not found';
  END IF;

  IF NOT public.has_facility_access(uid, v_bed.facility_id) THEN
    RAISE EXCEPTION 'Facility access required';
  END IF;

  IF v_bed.status = 'occupied' OR v_bed.patient_id IS NOT NULL OR v_bed.admission_id IS NOT NULL THEN
    RAISE EXCEPTION 'Occupied or patient-linked beds must use the inpatient movement or discharge workflow';
  END IF;

  UPDATE public.ward_beds
  SET status = _status,
      notes = COALESCE(NULLIF(pg_catalog.btrim(_notes), ''), notes),
      updated_at = now(),
      released_at = CASE WHEN _status = 'available' THEN COALESCE(released_at, now()) ELSE released_at END
  WHERE id = v_bed.id;

  RETURN pg_catalog.jsonb_build_object(
    'bed_id', v_bed.id,
    'status', _status
  );
END;
$function$;
