-- Fertility workflow security reconciliation.
CREATE OR REPLACE FUNCTION public.create_fertility_cycle_workflow(_patient_id UUID,_partner_name TEXT DEFAULT NULL,_cycle_type TEXT DEFAULT 'IVF',_start_date DATE DEFAULT CURRENT_DATE,_protocol TEXT DEFAULT NULL)
RETURNS public.fertility_cycles LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_cycle public.fertility_cycles; v_cycle_number INTEGER;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Insufficient role for fertility workflow'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
 IF upper(trim(_cycle_type)) NOT IN ('IVF','IUI','ICSI','FET') THEN RAISE EXCEPTION 'Unsupported fertility cycle type'; END IF;
 SELECT COALESCE(MAX(cycle_number),0)+1 INTO v_cycle_number FROM public.fertility_cycles WHERE patient_id=_patient_id;
 INSERT INTO public.fertility_cycles(patient_id,partner_name,cycle_type,cycle_number,start_date,protocol,status,assigned_specialist)
 VALUES(_patient_id,NULLIF(trim(_partner_name),''),upper(trim(_cycle_type)),v_cycle_number,_start_date,NULLIF(trim(_protocol),''),'active',auth.uid()) RETURNING * INTO v_cycle;
 PERFORM public.record_system_audit('fertility_cycle_created','fertility','fertility_cycle',v_cycle.id,'info',jsonb_build_object('patient_id',_patient_id,'cycle_type',v_cycle.cycle_type));
 RETURN v_cycle;
END; $$;

CREATE OR REPLACE FUNCTION public.record_fertility_monitoring_workflow(_cycle_id UUID,_visit_date DATE,_cycle_day INTEGER DEFAULT NULL,_estradiol NUMERIC DEFAULT NULL,_lh NUMERIC DEFAULT NULL,_fsh NUMERIC DEFAULT NULL,_progesterone NUMERIC DEFAULT NULL,_follicle_count_left INTEGER DEFAULT NULL,_follicle_count_right INTEGER DEFAULT NULL,_endometrial_thickness NUMERIC DEFAULT NULL,_medication_adjustments TEXT DEFAULT NULL)
RETURNS public.fertility_monitoring LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_row public.fertility_monitoring;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Insufficient role for fertility workflow'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.fertility_cycles WHERE id=_cycle_id) THEN RAISE EXCEPTION 'Fertility cycle not found'; END IF;
 IF _visit_date IS NULL THEN RAISE EXCEPTION 'Visit date is required'; END IF;
 IF _cycle_day IS NOT NULL AND _cycle_day<1 THEN RAISE EXCEPTION 'Cycle day must be positive'; END IF;
 IF _follicle_count_left IS NOT NULL AND _follicle_count_left<0 THEN RAISE EXCEPTION 'Left follicle count cannot be negative'; END IF;
 IF _follicle_count_right IS NOT NULL AND _follicle_count_right<0 THEN RAISE EXCEPTION 'Right follicle count cannot be negative'; END IF;
 IF _endometrial_thickness IS NOT NULL AND _endometrial_thickness<0 THEN RAISE EXCEPTION 'Endometrial thickness cannot be negative'; END IF;
 INSERT INTO public.fertility_monitoring(cycle_id,visit_date,cycle_day,estradiol,lh,fsh,progesterone,follicle_count_left,follicle_count_right,endometrial_thickness,medication_adjustments,recorded_by)
 VALUES(_cycle_id,_visit_date,_cycle_day,_estradiol,_lh,_fsh,_progesterone,_follicle_count_left,_follicle_count_right,_endometrial_thickness,NULLIF(trim(_medication_adjustments),''),auth.uid()) RETURNING * INTO v_row;
 PERFORM public.record_system_audit('fertility_monitoring_recorded','fertility','fertility_monitoring',v_row.id,'info',jsonb_build_object('cycle_id',_cycle_id,'visit_date',_visit_date));
 RETURN v_row;
END; $$;

CREATE OR REPLACE FUNCTION public.transition_fertility_cycle_workflow(_cycle_id UUID,_status TEXT,_outcome TEXT DEFAULT NULL)
RETURNS public.fertility_cycles LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_cycle public.fertility_cycles;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Insufficient role for fertility workflow'; END IF;
 IF lower(trim(_status)) NOT IN ('active','completed','cancelled','successful','unsuccessful') THEN RAISE EXCEPTION 'Unsupported fertility cycle status'; END IF;
 UPDATE public.fertility_cycles SET status=lower(trim(_status)),outcome=NULLIF(trim(_outcome),''),updated_at=now() WHERE id=_cycle_id RETURNING * INTO v_cycle;
 IF NOT FOUND THEN RAISE EXCEPTION 'Fertility cycle not found'; END IF;
 PERFORM public.record_system_audit('fertility_cycle_transitioned','fertility','fertility_cycle',v_cycle.id,'info',jsonb_build_object('status',v_cycle.status,'outcome',v_cycle.outcome));
 RETURN v_cycle;
END; $$;

REVOKE ALL ON FUNCTION public.create_fertility_cycle_workflow(UUID,TEXT,TEXT,DATE,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_fertility_monitoring_workflow(UUID,DATE,INTEGER,NUMERIC,NUMERIC,NUMERIC,NUMERIC,INTEGER,INTEGER,NUMERIC,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.transition_fertility_cycle_workflow(UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_fertility_cycle_workflow(UUID,TEXT,TEXT,DATE,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_fertility_monitoring_workflow(UUID,DATE,INTEGER,NUMERIC,NUMERIC,NUMERIC,NUMERIC,INTEGER,INTEGER,NUMERIC,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_fertility_cycle_workflow(UUID,TEXT,TEXT) TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.fertility_cycles FROM authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.fertility_monitoring FROM authenticated;
GRANT SELECT ON public.fertility_cycles,public.fertility_monitoring TO authenticated;
