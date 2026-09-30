BEGIN;

-- Restore explicit facility context required by clinical lineage workflows.
-- This does not enable the deferred two-facility isolation model.

CREATE OR REPLACE FUNCTION public.current_user_facility_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'pg_catalog, public'
AS $function$
  SELECT COALESCE(
    (SELECT uaf.facility_id
     FROM public.user_active_facilities uaf
     JOIN public.facility_memberships fm
       ON fm.user_id=uaf.user_id AND fm.facility_id=uaf.facility_id AND fm.is_active=true
     WHERE uaf.user_id=(SELECT auth.uid())
       AND EXISTS (SELECT 1 FROM public.healthcare_facilities hf WHERE hf.id=uaf.facility_id AND hf.is_active=true)
     LIMIT 1),
    (SELECT fm.facility_id
     FROM public.facility_memberships fm
     JOIN public.healthcare_facilities hf ON hf.id=fm.facility_id AND hf.is_active=true
     WHERE fm.user_id=(SELECT auth.uid()) AND fm.is_active=true
     GROUP BY fm.facility_id
     HAVING count(*)=1
     ORDER BY fm.facility_id
     LIMIT 1)
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_user_facilities()
RETURNS TABLE(facility_id uuid,facility_name text,facility_code text,facility_type text,is_active boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='pg_catalog, public'
AS $function$
DECLARE uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 RETURN QUERY
 SELECT hf.id,hf.name,hf.facility_code,hf.facility_type,hf.is_active
 FROM public.healthcare_facilities hf
 WHERE hf.is_active=true
   AND (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)
        OR EXISTS (SELECT 1 FROM public.facility_memberships fm WHERE fm.user_id=uid AND fm.facility_id=hf.id AND fm.is_active=true))
 ORDER BY hf.name,hf.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_active_facility_context(_facility_id uuid)
RETURNS public.healthcare_facilities
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog, public'
AS $function$
DECLARE uid uuid:=auth.uid(); result public.healthcare_facilities;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT * INTO result FROM public.healthcare_facilities hf WHERE hf.id=_facility_id AND hf.is_active=true;
 IF result.id IS NULL THEN RAISE EXCEPTION 'Active facility is required'; END IF;
 IF NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role) OR public.has_facility_access(uid,_facility_id)) THEN RAISE EXCEPTION 'Facility access required'; END IF;
 INSERT INTO public.user_active_facilities(user_id,facility_id,updated_at) VALUES(uid,_facility_id,now())
 ON CONFLICT(user_id) DO UPDATE SET facility_id=EXCLUDED.facility_id,updated_at=now();
 RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ensure_encounter_facility_attribution(_encounter_id uuid)
RETURNS public.encounters
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog, public'
AS $function$
DECLARE uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id(); v_enc public.encounters; v_patient_facility uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to establish encounter facility context'; END IF;
 IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before continuing clinical documentation'; END IF;
 SELECT * INTO v_enc FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF v_enc.id IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 IF v_enc.facility_id IS NOT NULL AND v_enc.facility_id<>v_facility THEN RAISE EXCEPTION 'Encounter belongs to a different facility context'; END IF;
 SELECT p.facility_id INTO v_patient_facility FROM public.patients p WHERE p.id=v_enc.patient_id FOR UPDATE;
 IF v_patient_facility IS NOT NULL AND v_patient_facility<>v_facility THEN RAISE EXCEPTION 'Patient belongs to a different facility context'; END IF;
 IF v_enc.facility_id IS NULL THEN UPDATE public.encounters SET facility_id=v_facility,updated_at=now() WHERE id=v_enc.id RETURNING * INTO v_enc; END IF;
 IF v_patient_facility IS NULL THEN UPDATE public.patients SET facility_id=v_facility,updated_at=now() WHERE id=v_enc.patient_id; END IF;
 RETURN v_enc;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_encounter_workflow(_patient_id uuid,_symptoms text DEFAULT NULL::text,_clerking_notes text DEFAULT NULL::text)
RETURNS public.encounters
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog, public'
AS $function$
DECLARE result public.encounters; uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id(); v_admission_id uuid; v_initial_encounter_id uuid; v_inherit boolean:=true; v_patient_facility uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role) OR public.has_role(uid,'practitioner'::public.app_role) OR public.has_role(uid,'nurse'::public.app_role) OR public.has_role(uid,'midwife'::public.app_role) OR public.has_role(uid,'specialist_nurse'::public.app_role)) THEN RAISE EXCEPTION 'Only authorized clinical staff may create encounters'; END IF;
 IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before creating an encounter'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=_patient_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Patient does not exist'; END IF;
 IF v_patient_facility IS NOT NULL AND v_patient_facility<>v_facility THEN RAISE EXCEPTION 'Patient belongs to a different facility context'; END IF;
 IF v_patient_facility IS NULL THEN UPDATE public.patients SET facility_id=v_facility,updated_at=now() WHERE id=_patient_id; END IF;
 SELECT id,coalesce(inherit_inpatient_diagnoses,true) INTO v_admission_id,v_inherit FROM public.admissions a CROSS JOIN LATERAL (SELECT coalesce(fc.inherit_inpatient_diagnoses,true) inherit_inpatient_diagnoses FROM public.facility_configuration fc ORDER BY fc.created_at ASC LIMIT 1) cfg WHERE a.patient_id=_patient_id AND a.status='admitted' AND (a.facility_id IS NULL OR a.facility_id=v_facility) ORDER BY a.admitted_at ASC NULLS FIRST,a.created_at ASC LIMIT 1;
 INSERT INTO public.encounters(patient_id,facility_id,symptoms,clerking_notes,practitioner_id,status,admission_id) VALUES(_patient_id,v_facility,nullif(trim(_symptoms),''),nullif(trim(_clerking_notes),''),uid,'draft',v_admission_id) RETURNING * INTO result;
 IF v_admission_id IS NOT NULL AND v_inherit THEN
   SELECT e.id INTO v_initial_encounter_id FROM public.encounters e WHERE e.admission_id=v_admission_id AND e.id<>result.id AND (e.facility_id IS NULL OR e.facility_id=v_facility) ORDER BY e.created_at ASC,e.id ASC LIMIT 1;
   IF v_initial_encounter_id IS NOT NULL THEN
     INSERT INTO public.diagnoses(encounter_id,diagnosis,is_principal,icd_code,ai_suggested) SELECT result.id,d.diagnosis,d.is_principal,d.icd_code,d.ai_suggested FROM public.diagnoses d WHERE d.encounter_id=v_initial_encounter_id;
     SELECT d.diagnosis INTO result.principal_diagnosis FROM public.diagnoses d WHERE d.encounter_id=result.id AND d.is_principal=true ORDER BY d.created_at ASC,d.id ASC LIMIT 1;
     UPDATE public.encounters SET principal_diagnosis=result.principal_diagnosis,updated_at=now() WHERE id=result.id RETURNING * INTO result;
     PERFORM public.record_system_audit('encounter_diagnoses_inherited','clinical','encounter',result.id,'info',jsonb_build_object('patient_id',result.patient_id,'admission_id',v_admission_id,'source_encounter_id',v_initial_encounter_id,'facility_id',v_facility));
   END IF;
 END IF;
 RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.add_encounter_diagnosis(_encounter_id uuid,_diagnosis text,_icd_code text DEFAULT NULL::text)
RETURNS public.diagnoses
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog, public'
AS $function$
DECLARE uid uuid:=auth.uid(); result public.diagnoses; normalized_code text:=NULLIF(pg_catalog.upper(pg_catalog.btrim(_icd_code)),''); v_enc public.encounters;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to add diagnoses'; END IF;
 v_enc:=public.ensure_encounter_facility_attribution(_encounter_id);
 IF v_enc.status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Completed or cancelled encounters are read-only'; END IF;
 IF NULLIF(pg_catalog.btrim(_diagnosis),'') IS NULL THEN RAISE EXCEPTION 'Diagnosis is required'; END IF;
 IF normalized_code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.icd_codes WHERE code=normalized_code) THEN RAISE EXCEPTION 'Diagnosis code is not in the approved ICD-10/STG catalogue'; END IF;
 INSERT INTO public.diagnoses(encounter_id,diagnosis,icd_code,is_principal,facility_id) VALUES(_encounter_id,pg_catalog.btrim(_diagnosis),normalized_code,false,v_enc.facility_id) RETURNING * INTO result;
 RETURN result;
END;
$function$;

REVOKE ALL ON TABLE public.user_active_facilities FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_user_facilities() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.set_active_facility_context(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.ensure_encounter_facility_attribution(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_encounter_workflow(uuid,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.add_encounter_diagnosis(uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_user_facilities() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_active_facility_context(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_encounter_facility_attribution(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_encounter_workflow(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_encounter_diagnosis(uuid,text,text) TO authenticated;

INSERT INTO public.user_active_facilities(user_id,facility_id,updated_at)
SELECT fm.user_id,fm.facility_id,now()
FROM public.facility_memberships fm JOIN public.healthcare_facilities hf ON hf.id=fm.facility_id AND hf.is_active=true
WHERE fm.is_active=true GROUP BY fm.user_id,fm.facility_id HAVING count(*)=1
ON CONFLICT(user_id) DO NOTHING;

NOTIFY pgrst,'reload schema';
COMMIT;