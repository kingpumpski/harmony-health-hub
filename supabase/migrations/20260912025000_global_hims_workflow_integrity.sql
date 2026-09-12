-- Workflow integrity for the global HIMS operational modules.

CREATE OR REPLACE FUNCTION public.assign_ward_bed(_bed_id UUID, _patient_id UUID, _admission_id UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b public.ward_beds%ROWTYPE; uid UUID := auth.uid();
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
 SELECT * INTO b FROM public.ward_beds WHERE id=_bed_id FOR UPDATE;
 IF b.id IS NULL THEN RAISE EXCEPTION 'Bed not found'; END IF;
 IF b.status <> 'available' OR b.patient_id IS NOT NULL THEN RAISE EXCEPTION 'Bed is not available'; END IF;
 UPDATE public.ward_beds SET patient_id=_patient_id, admission_id=_admission_id, status='occupied', occupied_at=now(), released_at=NULL WHERE id=_bed_id;
 RETURN jsonb_build_object('bed_id',_bed_id,'status','occupied','patient_id',_patient_id);
END; $$;
GRANT EXECUTE ON FUNCTION public.assign_ward_bed(UUID,UUID,UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.release_ward_bed(_bed_id UUID, _notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid();
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
 UPDATE public.ward_beds SET patient_id=NULL, admission_id=NULL, status='cleaning', released_at=now(), notes=COALESCE(_notes,notes) WHERE id=_bed_id AND status='occupied';
 IF NOT FOUND THEN RAISE EXCEPTION 'Occupied bed not found'; END IF;
 RETURN jsonb_build_object('bed_id',_bed_id,'status','cleaning');
END; $$;
GRANT EXECUTE ON FUNCTION public.release_ward_bed(UUID,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_transfusion_event(_record_id UUID, _status TEXT, _reaction_observed BOOLEAN DEFAULT false, _reaction_notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); r public.transfusion_records%ROWTYPE;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN ('issued','running','completed','stopped','cancelled') THEN RAISE EXCEPTION 'Invalid transfusion status'; END IF;
 SELECT * INTO r FROM public.transfusion_records WHERE id=_record_id FOR UPDATE;
 IF r.id IS NULL THEN RAISE EXCEPTION 'Transfusion record not found'; END IF;
 UPDATE public.transfusion_records SET status=_status, reaction_observed=_reaction_observed, reaction_notes=CASE WHEN _reaction_observed THEN _reaction_notes ELSE reaction_notes END,
 started_at=CASE WHEN _status='running' AND started_at IS NULL THEN now() ELSE started_at END,
 completed_at=CASE WHEN _status IN ('completed','stopped') THEN now() ELSE completed_at END,
 administered_by=COALESCE(administered_by,uid) WHERE id=_record_id;
 RETURN jsonb_build_object('record_id',_record_id,'status',_status,'reaction_observed',_reaction_observed);
END; $$;
GRANT EXECUTE ON FUNCTION public.record_transfusion_event(UUID,TEXT,BOOLEAN,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.transition_emergency_case(_case_id UUID, _status TEXT, _disposition TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid();
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN ('waiting','triage','treatment','observation','admitted','discharged','referred','left_without_being_seen','cancelled') THEN RAISE EXCEPTION 'Invalid emergency status'; END IF;
 UPDATE public.emergency_cases SET status=_status, disposition=COALESCE(_disposition,disposition), disposition_at=CASE WHEN _status IN ('admitted','discharged','referred','left_without_being_seen','cancelled') THEN now() ELSE disposition_at END, assigned_officer=COALESCE(assigned_officer,uid) WHERE id=_case_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Emergency case not found'; END IF;
 RETURN jsonb_build_object('case_id',_case_id,'status',_status);
END; $$;
GRANT EXECUTE ON FUNCTION public.transition_emergency_case(UUID,TEXT,TEXT) TO authenticated;
