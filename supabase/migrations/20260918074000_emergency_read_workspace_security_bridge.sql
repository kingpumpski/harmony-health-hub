-- Role-scoped emergency read workspace.
CREATE OR REPLACE FUNCTION public.get_emergency_workspace(_limit integer DEFAULT 200)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Emergency role required'; END IF;
 _limit:=LEAST(GREATEST(COALESCE(_limit,200),1),500);
 SELECT jsonb_build_object('patients',COALESCE((SELECT jsonb_agg(to_jsonb(p)) FROM (SELECT id,patient_code,first_name,last_name FROM public.patients WHERE status<>'inactive' ORDER BY first_name,last_name LIMIT _limit)p),'[]'::jsonb),'cases',COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.arrival_time DESC) FROM (SELECT id,patient_id,chief_complaint,acuity,arrival_mode,assigned_officer,status,arrival_time FROM public.emergency_cases ORDER BY arrival_time DESC LIMIT _limit)e),'[]'::jsonb)) INTO result; RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.get_emergency_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_emergency_workspace(integer) TO authenticated;
