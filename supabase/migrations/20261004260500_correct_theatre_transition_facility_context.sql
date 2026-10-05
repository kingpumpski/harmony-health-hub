-- Corrective hardening: enforce patient/facility context on theatre lifecycle transitions.
DROP FUNCTION IF EXISTS public.transition_theatre_case(uuid,text,text);

CREATE FUNCTION public.transition_theatre_case(_case_id uuid,_status text,_cancellation_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 uid uuid:=auth.uid();
 c public.theatre_cases%ROWTYPE;
 es text;
 allowed boolean:=false;
 patient_facility uuid;
 active_facility uuid;
BEGIN
 IF uid IS NULL OR NOT(
   public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'system_superuser')
   OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')
 ) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN('requested','approved','scheduled','in_progress','completed','cancelled','postponed') THEN RAISE EXCEPTION 'Invalid theatre status'; END IF;
 SELECT * INTO c FROM public.theatre_cases WHERE id=_case_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Theatre case not found'; END IF;
 IF c.patient_id IS NULL THEN RAISE EXCEPTION 'Theatre case patient attribution is unresolved'; END IF;
 PERFORM public.assert_patient_facility_context(c.patient_id);
 SELECT facility_id INTO patient_facility FROM public.patients WHERE id=c.patient_id;
 IF patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;
 IF c.facility_id IS NOT NULL AND c.facility_id IS DISTINCT FROM patient_facility THEN RAISE EXCEPTION 'Theatre case facility does not match patient facility'; END IF;
 active_facility:=public.current_user_facility_id();
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'system_superuser'))
    AND (active_facility IS NULL OR active_facility IS DISTINCT FROM patient_facility) THEN
   RAISE EXCEPTION 'Theatre case belongs to a different facility context';
 END IF;
 IF c.status IN('completed','cancelled') AND _status<>c.status THEN RAISE EXCEPTION 'Closed theatre case cannot be reopened'; END IF;
 IF c.encounter_id IS NOT NULL THEN
   SELECT status INTO es FROM public.encounters WHERE id=c.encounter_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
   IF es IN('completed','cancelled') AND _status NOT IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot modify theatre case for a closed encounter'; END IF;
 END IF;
 allowed:=(_status='approved' AND c.status='requested')
   OR (_status='scheduled' AND c.status='approved')
   OR (_status='in_progress' AND c.status='scheduled')
   OR (_status='completed' AND c.status='in_progress')
   OR (_status='cancelled' AND c.status IN('requested','approved','scheduled','postponed'))
   OR (_status='postponed' AND c.status IN('requested','approved','scheduled'));
 IF NOT allowed AND _status<>c.status THEN RAISE EXCEPTION 'Invalid theatre lifecycle transition'; END IF;
 IF _status IN('cancelled','postponed') AND NULLIF(pg_catalog.btrim(COALESCE(_cancellation_reason,'')),'') IS NULL THEN RAISE EXCEPTION 'A reason is required for cancellation or postponement'; END IF;
 UPDATE public.theatre_cases
 SET status=_status,notes=CASE WHEN _status IN('cancelled','postponed') THEN NULLIF(pg_catalog.btrim(_cancellation_reason),'') ELSE notes END,
     facility_id=COALESCE(facility_id,patient_facility),updated_at=pg_catalog.now()
 WHERE id=c.id;
 PERFORM public.record_system_audit('theatre_case_transitioned','theatre','theatre_case',c.id,'info',
   jsonb_build_object('patient_id',c.patient_id,'facility_id',patient_facility,'status',_status));
 RETURN jsonb_build_object('case_id',c.id,'status',_status);
END;
$function$;

REVOKE ALL ON FUNCTION public.transition_theatre_case(uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.transition_theatre_case(uuid,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.transition_theatre_case(uuid,text,text) TO authenticated;
