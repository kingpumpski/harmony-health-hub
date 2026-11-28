-- Facility administrators and IT administrators must not bypass facility context
-- in emergency, theatre, or transfusion lifecycle RPCs. Only system_superuser
-- may operate across facilities. Apply exact guarded source repairs to preserve
-- existing workflow state machines and RPC signatures.
DO $migration$
DECLARE
  v_oid oid;
  src text;
  original text;
  old_text text;
  new_text text;
  changed integer;
BEGIN
  SELECT p.oid INTO v_oid
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='transition_emergency_case'
    AND p.pronargs=3
    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='_case_id uuid, _status text, _disposition text';
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Expected transition_emergency_case(uuid,text,text) was not found'; END IF;
  src:=pg_catalog.pg_get_functiondef(v_oid); original:=src;

  old_text := 'DECLARE uid uuid:=auth.uid(); c public.emergency_cases%ROWTYPE;';
  new_text := 'DECLARE uid uuid:=auth.uid(); c public.emergency_cases%ROWTYPE; patient_facility uuid; active_facility uuid;';
  changed := (pg_catalog.length(src)-pg_catalog.length(pg_catalog.replace(src,old_text,'')))/pg_catalog.length(old_text);
  IF changed<>1 THEN RAISE EXCEPTION 'Emergency declaration anchor count mismatch: %',changed; END IF;
  src:=pg_catalog.replace(src,old_text,new_text);

  old_text := 'public.has_role(uid,''specialist_nurse'')) THEN RAISE EXCEPTION ''Clinical role required'';';
  new_text := 'public.has_role(uid,''specialist_nurse'') OR public.has_role(uid,''system_superuser'')) THEN RAISE EXCEPTION ''Clinical role required'';';
  changed := (pg_catalog.length(src)-pg_catalog.length(pg_catalog.replace(src,old_text,'')))/pg_catalog.length(old_text);
  IF changed<>1 THEN RAISE EXCEPTION 'Emergency role gate anchor count mismatch: %',changed; END IF;
  src:=pg_catalog.replace(src,old_text,new_text);

  old_text := 'PERFORM public.assert_patient_facility_context(c.patient_id);' || E'\n IF c.facility_id IS DISTINCT FROM (SELECT p.facility_id FROM public.patients p WHERE p.id=c.patient_id) THEN RAISE EXCEPTION ''Emergency case facility does not match patient facility''; END IF;';
  new_text := 'PERFORM public.assert_patient_facility_context(c.patient_id);' || E'\n SELECT p.facility_id INTO patient_facility FROM public.patients p WHERE p.id=c.patient_id;' ||
    E'\n IF patient_facility IS NULL THEN RAISE EXCEPTION ''Emergency patient facility attribution is unresolved''; END IF;' ||
    E'\n IF c.facility_id IS DISTINCT FROM patient_facility THEN RAISE EXCEPTION ''Emergency case facility does not match patient facility''; END IF;' ||
    E'\n active_facility:=public.current_user_facility_id();' ||
    E'\n IF NOT public.has_role(uid,''system_superuser'') AND (active_facility IS NULL OR active_facility IS DISTINCT FROM patient_facility) THEN RAISE EXCEPTION ''Emergency case belongs to a different facility context''; END IF;';
  changed := (pg_catalog.length(src)-pg_catalog.length(pg_catalog.replace(src,old_text,'')))/pg_catalog.length(old_text);
  IF changed<>1 THEN RAISE EXCEPTION 'Emergency facility anchor count mismatch: %',changed; END IF;
  src:=pg_catalog.replace(src,old_text,new_text);
  IF src=original THEN RAISE EXCEPTION 'Emergency facility repair made no changes'; END IF;
  EXECUTE src;

  SELECT p.oid INTO v_oid
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='transition_theatre_case' AND p.pronargs=3
    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='_case_id uuid, _status text, _cancellation_reason text';
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Expected transition_theatre_case(uuid,text,text) was not found'; END IF;
  src:=pg_catalog.pg_get_functiondef(v_oid); original:=src;
  old_text := 'IF NOT(public.has_role(uid,''admin'') OR public.has_role(uid,''it_admin'') OR public.has_role(uid,''system_superuser''))' ||
    E'\n    AND (active_facility IS NULL OR active_facility IS DISTINCT FROM patient_facility) THEN';
  new_text := 'IF NOT public.has_role(uid,''system_superuser'')' ||
    E'\n    AND (active_facility IS NULL OR active_facility IS DISTINCT FROM patient_facility) THEN';
  changed := (pg_catalog.length(src)-pg_catalog.length(pg_catalog.replace(src,old_text,'')))/pg_catalog.length(old_text);
  IF changed<>1 THEN RAISE EXCEPTION 'Theatre facility bypass anchor count mismatch: %',changed; END IF;
  src:=pg_catalog.replace(src,old_text,new_text);
  IF src=original THEN RAISE EXCEPTION 'Theatre facility repair made no changes'; END IF;
  EXECUTE src;

  SELECT p.oid INTO v_oid
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='record_transfusion_event' AND p.pronargs=4
    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='_record_id uuid, _status text, _reaction_observed boolean, _reaction_notes text';
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Expected record_transfusion_event(uuid,text,boolean,text) was not found'; END IF;
  src:=pg_catalog.pg_get_functiondef(v_oid); original:=src;

  old_text := 'public.has_role(uid,''specialist_nurse'')' || E'\n  ) THEN';
  new_text := 'public.has_role(uid,''specialist_nurse'') OR public.has_role(uid,''system_superuser'')' || E'\n  ) THEN';
  changed := (pg_catalog.length(src)-pg_catalog.length(pg_catalog.replace(src,old_text,'')))/pg_catalog.length(old_text);
  IF changed<>1 THEN RAISE EXCEPTION 'Transfusion role gate anchor count mismatch: %',changed; END IF;
  src:=pg_catalog.replace(src,old_text,new_text);

  old_text := 'IF NOT public.has_role(uid,''admin'')' ||
    E'\n     AND (active_facility IS NULL OR active_facility IS DISTINCT FROM patient_facility) THEN';
  new_text := 'IF NOT public.has_role(uid,''system_superuser'')' ||
    E'\n     AND (active_facility IS NULL OR active_facility IS DISTINCT FROM patient_facility) THEN';
  changed := (pg_catalog.length(src)-pg_catalog.length(pg_catalog.replace(src,old_text,'')))/pg_catalog.length(old_text);
  IF changed<>1 THEN RAISE EXCEPTION 'Transfusion facility bypass anchor count mismatch: %',changed; END IF;
  src:=pg_catalog.replace(src,old_text,new_text);
  IF src=original THEN RAISE EXCEPTION 'Transfusion facility repair made no changes'; END IF;
  EXECUTE src;
END
$migration$;

REVOKE ALL ON FUNCTION public.transition_emergency_case(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.transition_theatre_case(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_emergency_case(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_theatre_case(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) TO authenticated;
NOTIFY pgrst, 'reload schema';
