-- Harden bed creation against invalid/inactive ward references and duplicate
-- lifecycle state. ward_beds.ward_id references ward_units.id in the live schema.
CREATE OR REPLACE FUNCTION public.create_ward_bed(
  _ward_id uuid,
  _bed_number text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
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

  IF _ward_id IS NULL OR NULLIF(btrim(_bed_number),'') IS NULL THEN
    RAISE EXCEPTION 'Ward and bed number are required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.ward_units
    WHERE id=_ward_id
      AND active=true
  ) THEN
    RAISE EXCEPTION 'Active ward unit not found';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.ward_beds
    WHERE ward_id=_ward_id
      AND lower(btrim(bed_number))=lower(btrim(_bed_number))
  ) THEN
    RAISE EXCEPTION 'Bed number already exists in this ward';
  END IF;

  INSERT INTO public.ward_beds(
    ward_id,bed_number,status,patient_id,admission_id,created_at,updated_at
  )
  VALUES (
    _ward_id,btrim(_bed_number),'available',NULL,NULL,now(),now()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_ward_bed(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_ward_bed(uuid,text) TO authenticated;
