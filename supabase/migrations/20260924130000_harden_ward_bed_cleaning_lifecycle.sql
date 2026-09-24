-- Harden the ward-bed cleaning lifecycle: only a deliberately completed
-- cleaning operation may return a bed to the available pool.
CREATE OR REPLACE FUNCTION public.complete_ward_bed_cleaning(
  _bed_id uuid,
  _notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  b public.ward_beds%ROWTYPE;
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

  SELECT * INTO b
  FROM public.ward_beds
  WHERE id=_bed_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bed not found';
  END IF;

  IF b.status <> 'cleaning' THEN
    RAISE EXCEPTION 'Bed is not awaiting cleaning completion';
  END IF;

  IF b.patient_id IS NOT NULL OR b.admission_id IS NOT NULL THEN
    RAISE EXCEPTION 'Cleaning bed still has patient context';
  END IF;

  UPDATE public.ward_beds
  SET status='available',
      released_at=COALESCE(released_at,now()),
      notes=COALESCE(_notes,notes),
      updated_at=now()
  WHERE id=_bed_id
    AND status='cleaning'
    AND patient_id IS NULL
    AND admission_id IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bed state changed before cleaning could be completed';
  END IF;

  RETURN jsonb_build_object('bed_id',_bed_id,'status','available');
END;
$function$;

REVOKE ALL ON FUNCTION public.complete_ward_bed_cleaning(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_ward_bed_cleaning(uuid,text) TO authenticated;
