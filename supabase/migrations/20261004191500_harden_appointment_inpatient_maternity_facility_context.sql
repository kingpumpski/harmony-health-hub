CREATE OR REPLACE FUNCTION public.create_patient_appointment(
  _patient_id uuid,
  _scheduled_at timestamp with time zone,
  _department text DEFAULT NULL::text,
  _reason text DEFAULT NULL::text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE uid uuid:=auth.uid(); pf uuid; v_id uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'front_desk') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Appointment creation denied'; END IF;
 pf:=public.assert_patient_facility_context(_patient_id);
 v_id:=(public.create_appointment_workflow(_patient_id,_scheduled_at,_department,_reason)).id;
 RETURN pg_catalog.jsonb_build_object('appointment_id',v_id,'facility_id',pf);
END;$function$;

CREATE OR REPLACE FUNCTION public.create_inpatient_review(
 _admission_id uuid,
 _review_type text DEFAULT 'ward_review'::text,
 _findings text DEFAULT NULL::text,
 _assessment text DEFAULT NULL::text,
 _plan text DEFAULT NULL::text
)
RETURNS public.inpatient_reviews LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE uid uuid:=auth.uid(); v_admission public.admissions%ROWTYPE; v_review public.inpatient_reviews; v_type text:=NULLIF(pg_catalog.btrim(coalesce(_review_type,'')),''); pf uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Inpatient review creation is not permitted'; END IF;
 IF _admission_id IS NULL THEN RAISE EXCEPTION 'Admission is required'; END IF;
 IF v_type IS NULL THEN RAISE EXCEPTION 'Review type is required'; END IF;
 SELECT * INTO v_admission FROM public.admissions WHERE id=_admission_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Admission not found'; END IF;
 IF v_admission.status <> 'admitted' THEN RAISE EXCEPTION 'Inpatient reviews require an active admitted admission'; END IF;
 IF v_admission.patient_id IS NULL THEN RAISE EXCEPTION 'Admission patient is required'; END IF;
 pf:=public.assert_patient_facility_context(v_admission.patient_id);
 IF v_admission.facility_id IS DISTINCT FROM pf THEN RAISE EXCEPTION 'Admission facility lineage mismatch'; END IF;
 INSERT INTO public.inpatient_reviews(admission_id,patient_id,review_type,reviewed_by,findings,plan,facility_id)
 VALUES(v_admission.id,v_admission.patient_id,v_type,uid,NULLIF(pg_catalog.btrim(coalesce(_findings,'')),''),NULLIF(pg_catalog.btrim(coalesce(_plan,'')),''),pf)
 RETURNING * INTO v_review;
 RETURN v_review;
END;$function$;

CREATE OR REPLACE FUNCTION public.create_maternity_episode_workflow(
 _patient_id uuid,_gravida integer DEFAULT NULL,_para integer DEFAULT NULL,_lmp date DEFAULT NULL,_edd date DEFAULT NULL,
 _risk_level text DEFAULT 'routine',_status text DEFAULT 'antenatal',_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE uid uuid:=auth.uid(); v_id uuid; pf uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Maternity episode creation is not permitted'; END IF;
 pf:=public.assert_patient_facility_context(_patient_id);
 IF _gravida IS NOT NULL AND _gravida<0 THEN RAISE EXCEPTION 'Gravida cannot be negative'; END IF;
 IF _para IS NOT NULL AND _para<0 THEN RAISE EXCEPTION 'Para cannot be negative'; END IF;
 IF _risk_level NOT IN ('routine','high','critical') THEN RAISE EXCEPTION 'Invalid maternity risk level'; END IF;
 IF _status NOT IN ('antenatal','labour','postpartum') THEN RAISE EXCEPTION 'Invalid maternity episode status'; END IF;
 INSERT INTO public.maternity_episodes(patient_id,gravida,para,lmp,edd,risk_level,status,notes,created_by,facility_id)
 VALUES(_patient_id,_gravida,_para,_lmp,_edd,_risk_level,_status,NULLIF(pg_catalog.btrim(_notes),''),uid,pf) RETURNING id INTO v_id;
 PERFORM public.record_system_audit('maternity_episode_created','maternity','maternity_episode',v_id,'info',pg_catalog.jsonb_build_object('patient_id',_patient_id,'risk_level',_risk_level,'status',_status,'facility_id',pf));
 RETURN pg_catalog.jsonb_build_object('episode_id',v_id,'status',_status,'facility_id',pf);
END;$function$;

REVOKE EXECUTE ON FUNCTION public.create_patient_appointment(uuid,timestamp with time zone,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_inpatient_review(uuid,text,text,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_maternity_episode_workflow(uuid,integer,integer,date,date,text,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_patient_appointment(uuid,timestamp with time zone,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_inpatient_review(uuid,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_maternity_episode_workflow(uuid,integer,integer,date,date,text,text,text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_patient_appointment(uuid,timestamptz,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_inpatient_review(uuid,text,text,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_maternity_episode_workflow(uuid,integer,integer,date,date,text,text,text) FROM PUBLIC;
NOTIFY pgrst,'reload schema';