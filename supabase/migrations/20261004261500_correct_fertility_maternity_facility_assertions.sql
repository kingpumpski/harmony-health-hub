-- Corrective facility-context hardening for fertility and maternity clinical workflows.
-- These functions already enforce facility equality; this forward migration adds the
-- canonical patient-context assertion required by the authorization boundary contract.

DROP FUNCTION IF EXISTS public.record_fertility_monitoring_workflow(uuid,date,integer,numeric,numeric,numeric,numeric,integer,integer,numeric,text);
CREATE FUNCTION public.record_fertility_monitoring_workflow(_cycle_id uuid,_visit_date date,_cycle_day integer DEFAULT NULL,_estradiol numeric DEFAULT NULL,_lh numeric DEFAULT NULL,_fsh numeric DEFAULT NULL,_progesterone numeric DEFAULT NULL,_follicle_count_left integer DEFAULT NULL,_follicle_count_right integer DEFAULT NULL,_endometrial_thickness numeric DEFAULT NULL,_medication_adjustments text DEFAULT NULL)
RETURNS public.fertility_monitoring LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE v_row public.fertility_monitoring; v_uid uuid:=auth.uid(); v_facility uuid; v_cycle_facility uuid; v_patient_id uuid;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(v_uid,'admin') OR public.has_role(v_uid,'it_admin') OR public.has_role(v_uid,'system_superuser') OR public.has_role(v_uid,'practitioner') OR public.has_role(v_uid,'nurse') OR public.has_role(v_uid,'midwife')) THEN RAISE EXCEPTION 'Insufficient role for fertility workflow'; END IF;
 SELECT patient_id,facility_id INTO v_patient_id,v_cycle_facility FROM public.fertility_cycles WHERE id=_cycle_id;
 IF v_patient_id IS NULL OR v_cycle_facility IS NULL THEN RAISE EXCEPTION 'Fertility cycle not found or facility attribution is unresolved'; END IF;
 PERFORM public.assert_patient_facility_context(v_patient_id);
 v_facility:=public.current_user_facility_id();
 IF NOT(public.has_role(v_uid,'admin') OR public.has_role(v_uid,'it_admin') OR public.has_role(v_uid,'system_superuser')) AND (v_facility IS NULL OR v_facility IS DISTINCT FROM v_cycle_facility) THEN RAISE EXCEPTION 'Fertility cycle belongs to a different facility context'; END IF;
 IF _visit_date IS NULL THEN RAISE EXCEPTION 'Visit date is required'; END IF;
 IF _cycle_day IS NOT NULL AND _cycle_day<1 THEN RAISE EXCEPTION 'Cycle day must be positive'; END IF;
 IF _follicle_count_left IS NOT NULL AND _follicle_count_left<0 THEN RAISE EXCEPTION 'Left follicle count cannot be negative'; END IF;
 IF _follicle_count_right IS NOT NULL AND _follicle_count_right<0 THEN RAISE EXCEPTION 'Right follicle count cannot be negative'; END IF;
 IF _endometrial_thickness IS NOT NULL AND _endometrial_thickness<0 THEN RAISE EXCEPTION 'Endometrial thickness cannot be negative'; END IF;
 INSERT INTO public.fertility_monitoring(cycle_id,visit_date,cycle_day,estradiol,lh,fsh,progesterone,follicle_count_left,follicle_count_right,endometrial_thickness,medication_adjustments,recorded_by) VALUES(_cycle_id,_visit_date,_cycle_day,_estradiol,_lh,_fsh,_progesterone,_follicle_count_left,_follicle_count_right,_endometrial_thickness,NULLIF(pg_catalog.btrim(_medication_adjustments),''),v_uid) RETURNING * INTO v_row;
 PERFORM public.record_system_audit('fertility_monitoring_recorded','fertility','fertility_monitoring',v_row.id,'info',jsonb_build_object('cycle_id',_cycle_id,'visit_date',_visit_date,'facility_id',v_cycle_facility));
 RETURN v_row;
END;
$function$;
REVOKE ALL ON FUNCTION public.record_fertility_monitoring_workflow(uuid,date,integer,numeric,numeric,numeric,numeric,integer,integer,numeric,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_fertility_monitoring_workflow(uuid,date,integer,numeric,numeric,numeric,numeric,integer,integer,numeric,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_fertility_monitoring_workflow(uuid,date,integer,numeric,numeric,numeric,numeric,integer,integer,numeric,text) TO authenticated;

DROP FUNCTION IF EXISTS public.record_maternity_observation_workflow(uuid,text,integer,numeric,integer,integer,numeric,integer,text,text,text);
CREATE FUNCTION public.record_maternity_observation_workflow(_episode_id uuid,_blood_pressure text DEFAULT NULL,_pulse integer DEFAULT NULL,_temperature numeric DEFAULT NULL,_fetal_heart_rate integer DEFAULT NULL,_contractions_per_10_min integer DEFAULT NULL,_cervical_dilation_cm numeric DEFAULT NULL,_effacement_percent integer DEFAULT NULL,_station text DEFAULT NULL,_membrane_status text DEFAULT NULL,_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE v_id uuid; v_patient_id uuid; v_episode_facility uuid; v_active_facility uuid; v_uid uuid:=auth.uid();
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(v_uid,'admin') OR public.has_role(v_uid,'it_admin') OR public.has_role(v_uid,'system_superuser') OR public.has_role(v_uid,'practitioner') OR public.has_role(v_uid,'nurse') OR public.has_role(v_uid,'midwife') OR public.has_role(v_uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Maternity observation recording is not permitted'; END IF;
 SELECT patient_id,facility_id INTO v_patient_id,v_episode_facility FROM public.maternity_episodes WHERE id=_episode_id AND status NOT IN('completed','cancelled');
 IF v_patient_id IS NULL OR v_episode_facility IS NULL THEN RAISE EXCEPTION 'Active maternity episode not found or facility attribution is unresolved'; END IF;
 PERFORM public.assert_patient_facility_context(v_patient_id);
 v_active_facility:=public.current_user_facility_id();
 IF NOT(public.has_role(v_uid,'admin') OR public.has_role(v_uid,'it_admin') OR public.has_role(v_uid,'system_superuser')) AND (v_active_facility IS NULL OR v_active_facility IS DISTINCT FROM v_episode_facility) THEN RAISE EXCEPTION 'Maternity episode belongs to a different facility context'; END IF;
 IF _pulse IS NOT NULL AND _pulse<0 THEN RAISE EXCEPTION 'Pulse cannot be negative'; END IF;
 IF _fetal_heart_rate IS NOT NULL AND _fetal_heart_rate<0 THEN RAISE EXCEPTION 'Fetal heart rate cannot be negative'; END IF;
 IF _effacement_percent IS NOT NULL AND (_effacement_percent<0 OR _effacement_percent>100) THEN RAISE EXCEPTION 'Effacement must be between 0 and 100'; END IF;
 IF _cervical_dilation_cm IS NOT NULL AND (_cervical_dilation_cm<0 OR _cervical_dilation_cm>10) THEN RAISE EXCEPTION 'Cervical dilation must be between 0 and 10 cm'; END IF;
 INSERT INTO public.maternity_observations(episode_id,blood_pressure,pulse,temperature,fetal_heart_rate,contractions_per_10_min,cervical_dilation_cm,effacement_percent,station,membrane_status,notes,recorded_by) VALUES(_episode_id,NULLIF(pg_catalog.btrim(_blood_pressure),''),_pulse,_temperature,_fetal_heart_rate,_contractions_per_10_min,_cervical_dilation_cm,_effacement_percent,NULLIF(pg_catalog.btrim(_station),''),NULLIF(pg_catalog.btrim(_membrane_status),''),NULLIF(pg_catalog.btrim(_notes),''),v_uid) RETURNING id INTO v_id;
 PERFORM public.record_system_audit('maternity_observation_recorded','maternity','maternity_observation',v_id,'info',jsonb_build_object('patient_id',v_patient_id,'episode_id',_episode_id,'facility_id',v_episode_facility));
 RETURN jsonb_build_object('observation_id',v_id,'episode_id',_episode_id);
END;
$function$;
REVOKE ALL ON FUNCTION public.record_maternity_observation_workflow(uuid,text,integer,numeric,integer,integer,numeric,integer,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_maternity_observation_workflow(uuid,text,integer,numeric,integer,integer,numeric,integer,text,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_maternity_observation_workflow(uuid,text,integer,numeric,integer,integer,numeric,integer,text,text,text) TO authenticated;
