-- Serialize legacy admission creation per patient and make the
-- optional canonical bed assignment atomic with the admission.
CREATE OR REPLACE FUNCTION public.create_admission_workflow(
  _patient_id uuid,
  _ward text,
  _bed text DEFAULT NULL,
  _reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid;
  v_ward_id uuid;
  v_bed_id uuid;
  v_existing_admission uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'practitioner')
    OR public.has_role(auth.uid(),'nurse')
    OR public.has_role(auth.uid(),'midwife')
  ) THEN
    RAISE EXCEPTION 'Admission creation is not permitted';
  END IF;

  IF _patient_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.patients WHERE id=_patient_id
  ) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  IF _ward IS NULL OR btrim(_ward)='' THEN
    RAISE EXCEPTION 'Ward is required';
  END IF;

  -- Serialize all legacy admission entry points for the same patient.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(_patient_id::text, 0)
  );

  SELECT a.id INTO v_existing_admission
  FROM public.admissions a
  WHERE a.patient_id=_patient_id
    AND a.status='admitted'
  ORDER BY a.admitted_at DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF v_existing_admission IS NOT NULL THEN
    RAISE EXCEPTION 'Patient already has an active admission';
  END IF;

  SELECT id INTO v_ward_id
  FROM public.ward_units
  WHERE active
    AND (
      id::text=btrim(_ward)
      OR lower(btrim(name))=lower(btrim(_ward))
      OR lower(btrim(code))=lower(btrim(_ward))
    )
  ORDER BY CASE
    WHEN id::text=btrim(_ward) THEN 0
    WHEN lower(btrim(code))=lower(btrim(_ward)) THEN 1
    ELSE 2
  END
  LIMIT 1;

  IF v_ward_id IS NULL THEN
    RAISE EXCEPTION 'Active ward not found';
  END IF;

  IF _bed IS NOT NULL AND btrim(_bed)<>'' THEN
    SELECT wb.id INTO v_bed_id
    FROM public.ward_beds wb
    WHERE wb.ward_id=v_ward_id
      AND lower(btrim(wb.bed_number))=lower(btrim(_bed))
    LIMIT 1
    FOR UPDATE;

    IF v_bed_id IS NULL THEN
      RAISE EXCEPTION 'Bed not found in selected ward';
    END IF;

    IF EXISTS(
      SELECT 1 FROM public.ward_beds
      WHERE id=v_bed_id
        AND (
          status <> 'available'
          OR patient_id IS NOT NULL
          OR admission_id IS NOT NULL
        )
    ) THEN
      RAISE EXCEPTION 'Selected bed is not available';
    END IF;
  END IF;

  INSERT INTO public.admissions(
    patient_id,ward,bed,reason,admitted_by,status,admitted_at
  )
  VALUES(
    _patient_id,
    (SELECT w.name FROM public.ward_units w WHERE w.id=v_ward_id),
    NULLIF(btrim(_bed),''),
    NULLIF(btrim(_reason),''),
    auth.uid(),
    'admitted',
    now()
  )
  RETURNING id INTO v_id;

  IF v_bed_id IS NOT NULL THEN
    UPDATE public.ward_beds
    SET patient_id=_patient_id,
        admission_id=v_id,
        status='occupied',
        occupied_at=now(),
        released_at=NULL,
        updated_at=now()
    WHERE id=v_bed_id
      AND status='available'
      AND patient_id IS NULL
      AND admission_id IS NULL;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Bed became unavailable during admission';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'admission_id',v_id,
    'status','admitted',
    'ward_id',v_ward_id,
    'bed_id',v_bed_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.create_admission_workflow(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_admission_workflow(uuid,text,text,text) TO authenticated;
