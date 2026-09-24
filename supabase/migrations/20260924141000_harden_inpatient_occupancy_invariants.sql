CREATE UNIQUE INDEX IF NOT EXISTS admissions_one_active_per_patient_uniq ON public.admissions(patient_id) WHERE status='admitted' AND patient_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ward_beds_one_occupied_per_patient_uniq ON public.ward_beds(patient_id) WHERE status='occupied' AND patient_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ward_beds_one_occupied_per_admission_uniq ON public.ward_beds(admission_id) WHERE status='occupied' AND admission_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.assign_ward_bed(_bed_id uuid,_patient_id uuid,_admission_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE uid uuid:=auth.uid(); b public.ward_beds%ROWTYPE; a public.admissions%ROWTYPE; v_existing_bed_id uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
 IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(_patient_id::text,0));
 SELECT * INTO b FROM public.ward_beds WHERE id=_bed_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Bed not found'; END IF;
 IF b.status<>'available' OR b.patient_id IS NOT NULL OR b.admission_id IS NOT NULL THEN RAISE EXCEPTION 'Bed is not available'; END IF;
 IF _admission_id IS NULL THEN
   SELECT * INTO a FROM public.admissions WHERE patient_id=_patient_id AND status='admitted' ORDER BY admitted_at DESC NULLS LAST LIMIT 1 FOR UPDATE;
 ELSE
   SELECT * INTO a FROM public.admissions WHERE id=_admission_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Admission not found'; END IF;
   IF a.patient_id IS DISTINCT FROM _patient_id THEN RAISE EXCEPTION 'Admission does not belong to patient'; END IF;
   IF a.status<>'admitted' THEN RAISE EXCEPTION 'Admission is not active'; END IF;
 END IF;
 IF a.id IS NULL THEN RAISE EXCEPTION 'An active inpatient admission is required'; END IF;
 SELECT wb.id INTO v_existing_bed_id FROM public.ward_beds wb WHERE wb.patient_id=_patient_id AND wb.status='occupied' AND wb.id<>b.id ORDER BY wb.occupied_at DESC NULLS LAST LIMIT 1 FOR UPDATE;
 IF v_existing_bed_id IS NOT NULL THEN RAISE EXCEPTION 'Patient is already assigned to another occupied bed'; END IF;
 UPDATE public.ward_beds SET patient_id=_patient_id,admission_id=a.id,status='occupied',occupied_at=now(),released_at=NULL,updated_at=now() WHERE id=b.id AND status='available' AND patient_id IS NULL AND admission_id IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Bed assignment changed before it could be completed'; END IF;
 UPDATE public.admissions SET ward=COALESCE((SELECT w.name FROM public.ward_units w WHERE w.id=b.ward_id),ward),bed=b.bed_number,updated_at=now() WHERE id=a.id;
 RETURN jsonb_build_object('bed_id',b.id,'admission_id',a.id,'ward_id',b.ward_id,'status','occupied','patient_id',_patient_id);
END;$function$;
REVOKE ALL ON FUNCTION public.assign_ward_bed(uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.assign_ward_bed(uuid,uuid,uuid) TO authenticated;