-- Next-generation admission / bed concurrency boundary.
-- Reuses canonical admissions and ward_beds tables; no duplicate inpatient infrastructure.

CREATE OR REPLACE FUNCTION public.create_admission_workflow(
  _patient_id UUID,
  _ward TEXT,
  _bed TEXT DEFAULT NULL,
  _reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_id UUID;
  v_bed public.ward_beds%ROWTYPE;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN
    RAISE EXCEPTION 'Admission creation is not permitted';
  END IF;
  IF _patient_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;
  IF EXISTS (SELECT 1 FROM public.admissions WHERE patient_id=_patient_id AND status='admitted' AND discharged_at IS NULL) THEN
    RAISE EXCEPTION 'Patient already has an active admission';
  END IF;
  IF NULLIF(btrim(_ward),'') IS NULL THEN RAISE EXCEPTION 'Ward is required'; END IF;

  IF NULLIF(btrim(_bed),'') IS NOT NULL THEN
    SELECT * INTO v_bed
    FROM public.ward_beds
    WHERE bed_number=btrim(_bed)
      AND status='available'
      AND patient_id IS NULL
      AND ward_id IN (SELECT id FROM public.ward_units WHERE name=btrim(_ward))
    FOR UPDATE;
    IF v_bed.id IS NULL THEN RAISE EXCEPTION 'Requested bed is not available in the selected ward'; END IF;
  END IF;

  INSERT INTO public.admissions(patient_id,ward,bed,reason,admitted_by,status,admitted_at)
  VALUES (_patient_id,btrim(_ward),NULLIF(btrim(_bed),''),NULLIF(btrim(_reason),''),uid,'admitted',now())
  RETURNING id INTO v_id;

  IF v_bed.id IS NOT NULL THEN
    UPDATE public.ward_beds
    SET patient_id=_patient_id, admission_id=v_id, status='occupied', occupied_at=now(), released_at=NULL, updated_at=now()
    WHERE id=v_bed.id;
  END IF;

  RETURN jsonb_build_object('admission_id',v_id,'status','admitted','bed_id',v_bed.id);
END; $$;

CREATE OR REPLACE FUNCTION public.discharge_admission_workflow(
  _admission_id UUID,
  _summary TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  uid UUID := auth.uid();
  a public.admissions%ROWTYPE;
  v_bed_id UUID;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN
    RAISE EXCEPTION 'Admission discharge is not permitted';
  END IF;

  SELECT * INTO a FROM public.admissions WHERE id=_admission_id FOR UPDATE;
  IF a.id IS NULL OR a.status <> 'admitted' OR a.discharged_at IS NOT NULL THEN
    RAISE EXCEPTION 'Admission not found or is no longer active';
  END IF;

  -- Inpatient nursing plans are clinical continuity records. Discharge cannot
  -- silently strand an active admission-linked plan; the plan must first be
  -- explicitly completed or cancelled through its own audited lifecycle RPC.
  IF EXISTS (
    SELECT 1
    FROM public.nursing_care_plans
    WHERE admission_id=_admission_id
      AND status='active'
  ) THEN
    RAISE EXCEPTION 'Active nursing care plans must be completed or cancelled before discharge';
  END IF;

  UPDATE public.admissions
  SET status='discharged', discharged_at=now(), discharge_summary=COALESCE(NULLIF(btrim(_summary),''),'Discharged from inpatient admission.')
  WHERE id=_admission_id;

  SELECT id INTO v_bed_id
  FROM public.ward_beds
  WHERE admission_id=_admission_id
  FOR UPDATE;

  IF v_bed_id IS NOT NULL THEN
    UPDATE public.ward_beds
    SET patient_id=NULL, admission_id=NULL, status='cleaning', released_at=now(), updated_at=now()
    WHERE id=v_bed_id;
  END IF;

  RETURN jsonb_build_object('admission_id',_admission_id,'status','discharged','bed_id',v_bed_id);
END; $$;

CREATE OR REPLACE FUNCTION public.assign_ward_bed(
  _bed_id UUID,
  _patient_id UUID,
  _admission_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  uid UUID := auth.uid();
  b public.ward_beds%ROWTYPE;
  a public.admissions%ROWTYPE;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
  IF _patient_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;

  SELECT * INTO b FROM public.ward_beds WHERE id=_bed_id FOR UPDATE;
  IF b.id IS NULL THEN RAISE EXCEPTION 'Bed not found'; END IF;
  IF b.status <> 'available' OR b.patient_id IS NOT NULL OR b.admission_id IS NOT NULL THEN RAISE EXCEPTION 'Bed is not available'; END IF;

  IF _admission_id IS NOT NULL THEN
    SELECT * INTO a FROM public.admissions WHERE id=_admission_id FOR UPDATE;
    IF a.id IS NULL OR a.patient_id <> _patient_id OR a.status <> 'admitted' OR a.discharged_at IS NOT NULL THEN
      RAISE EXCEPTION 'Admission is invalid or not active for this patient';
    END IF;
    IF EXISTS (SELECT 1 FROM public.ward_beds WHERE admission_id=_admission_id AND id<>_bed_id) THEN
      RAISE EXCEPTION 'Admission already has a bed';
    END IF;
  END IF;

  UPDATE public.ward_beds
  SET patient_id=_patient_id, admission_id=_admission_id, status='occupied', occupied_at=now(), released_at=NULL, updated_at=now()
  WHERE id=_bed_id;

  RETURN jsonb_build_object('bed_id',_bed_id,'status','occupied','patient_id',_patient_id,'admission_id',_admission_id);
END; $$;

CREATE OR REPLACE FUNCTION public.release_ward_bed(_bed_id UUID, _notes TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE uid UUID := auth.uid(); b public.ward_beds%ROWTYPE;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
  SELECT * INTO b FROM public.ward_beds WHERE id=_bed_id FOR UPDATE;
  IF b.id IS NULL OR b.status <> 'occupied' THEN RAISE EXCEPTION 'Occupied bed not found'; END IF;
  IF b.admission_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.admissions WHERE id=b.admission_id AND status='admitted' AND discharged_at IS NULL) THEN
    RAISE EXCEPTION 'Active admission must be discharged before releasing its bed';
  END IF;
  UPDATE public.ward_beds SET patient_id=NULL, admission_id=NULL, status='cleaning', released_at=now(), notes=COALESCE(NULLIF(btrim(_notes),''),notes), updated_at=now() WHERE id=_bed_id;
  RETURN jsonb_build_object('bed_id',_bed_id,'status','cleaning');
END; $$;

REVOKE ALL ON FUNCTION public.create_admission_workflow(UUID,TEXT,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.discharge_admission_workflow(UUID,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.assign_ward_bed(UUID,UUID,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.release_ward_bed(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_admission_workflow(UUID,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.discharge_admission_workflow(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_ward_bed(UUID,UUID,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_ward_bed(UUID,TEXT) TO authenticated;

REVOKE INSERT,UPDATE,DELETE ON TABLE public.admissions FROM authenticated;
REVOKE INSERT,UPDATE,DELETE ON TABLE public.beds FROM authenticated;
REVOKE INSERT,UPDATE,DELETE ON TABLE public.ward_beds FROM authenticated;

COMMENT ON TABLE public.admissions IS 'Admission lifecycle is server-authoritative; active-admission and bed consistency are enforced by workflow RPCs.';
COMMENT ON TABLE public.ward_beds IS 'Bed occupancy lifecycle is server-authoritative and row-locked to prevent concurrent assignment.';
