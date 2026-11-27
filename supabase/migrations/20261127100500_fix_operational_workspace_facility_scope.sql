-- Repair the operational workspace RPC's facility boundaries without rewriting protected history.
-- Facility administrators are facility-scoped; only system_superuser can read across facilities.
DO $migration$
DECLARE
  src text;
  original text;
  old_predicate text;
  new_predicate text;
  replacements integer;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO src
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname='get_operational_workspace'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='_module text, _limit integer';

  IF src IS NULL THEN
    RAISE EXCEPTION 'Expected get_operational_workspace(text,integer) definition was not found';
  END IF;
  original := src;

  old_predicate := 'AND (v_role NOT IN (''admin'',''it_admin'',''system_superuser'') OR v_facility IS NULL OR p.facility_id=v_facility)';
  new_predicate := 'AND (v_role = ''system_superuser'' OR (v_facility IS NOT NULL AND p.facility_id=v_facility AND a.facility_id=v_facility))';
  replacements := (pg_catalog.length(src)-pg_catalog.length(pg_catalog.replace(src,old_predicate,'')))/pg_catalog.length(old_predicate);
  IF replacements <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one appointment facility predicate, found %', replacements;
  END IF;
  src := pg_catalog.replace(src,old_predicate,new_predicate);

  old_predicate := '(v_platform_admin AND v_facility IS NULL OR p.facility_id=v_facility)';
  new_predicate := '(v_role = ''system_superuser'' OR (v_facility IS NOT NULL AND p.facility_id=v_facility))';
  replacements := (pg_catalog.length(src)-pg_catalog.length(pg_catalog.replace(src,old_predicate,'')))/pg_catalog.length(old_predicate);
  IF replacements <> 7 THEN
    RAISE EXCEPTION 'Expected seven patient-linked workspace facility predicates, found %', replacements;
  END IF;
  src := pg_catalog.replace(src,old_predicate,new_predicate);

  old_predicate := '(v_platform_admin AND v_facility IS NULL OR facility_id IS NULL OR facility_id=v_facility)';
  new_predicate := '(v_role = ''system_superuser'' OR (v_facility IS NOT NULL AND facility_id=v_facility))';
  replacements := (pg_catalog.length(src)-pg_catalog.length(pg_catalog.replace(src,old_predicate,'')))/pg_catalog.length(old_predicate);
  IF replacements <> 1 THEN
    RAISE EXCEPTION 'Expected one ward-unit facility predicate, found %', replacements;
  END IF;
  src := pg_catalog.replace(src,old_predicate,new_predicate);

  old_predicate := 'v_platform_admin AND v_facility IS NULL OR b.facility_id IS NULL OR b.facility_id=v_facility';
  new_predicate := 'v_role = ''system_superuser'' OR (v_facility IS NOT NULL AND b.facility_id=v_facility)';
  replacements := (pg_catalog.length(src)-pg_catalog.length(pg_catalog.replace(src,old_predicate,'')))/pg_catalog.length(old_predicate);
  IF replacements <> 1 THEN
    RAISE EXCEPTION 'Expected one ward-bed facility predicate, found %', replacements;
  END IF;
  src := pg_catalog.replace(src,old_predicate,new_predicate);

  old_predicate := 'FROM public.ai_clinical_sessions' || E'\\n      ORDER BY created_at DESC LIMIT v_limit)x),''[]''::jsonb)) INTO result;';
  new_predicate := 'FROM public.ai_clinical_sessions WHERE (v_role = ''system_superuser'' OR (v_facility IS NOT NULL AND facility_id=v_facility))' || E'\\n      ORDER BY created_at DESC LIMIT v_limit)x),''[]''::jsonb)) INTO result;';
  replacements := (pg_catalog.length(src)-pg_catalog.length(pg_catalog.replace(src,old_predicate,'')))/pg_catalog.length(old_predicate);
  IF replacements <> 1 THEN
    RAISE EXCEPTION 'Expected one AI-clinical session facility predicate anchor, found %', replacements;
  END IF;
  src := pg_catalog.replace(src,old_predicate,new_predicate);

  old_predicate := 'IF v_role IS NULL THEN RAISE EXCEPTION ''Staff profile required''; END IF;';
  new_predicate := old_predicate || E'\n  IF _module IN (''appointments'',''ward'',''nursing_care'',''emergency'',''handover'',''theatre'',''transfusion'',''insurance'',''medication_administration'')\n     AND v_role <> ''system_superuser'' AND v_facility IS NULL THEN\n    RAISE EXCEPTION ''Select an active facility to access this operational workspace'';\n  END IF;';
  replacements := (pg_catalog.length(src)-pg_catalog.length(pg_catalog.replace(src,old_predicate,'')))/pg_catalog.length(old_predicate);
  IF replacements <> 1 THEN
    RAISE EXCEPTION 'Expected one operational workspace role-resolution anchor, found %', replacements;
  END IF;
  src := pg_catalog.replace(src,old_predicate,new_predicate);

  IF src = original THEN
    RAISE EXCEPTION 'Operational workspace facility repair made no changes';
  END IF;
  EXECUTE src;
END
$migration$;

REVOKE ALL ON FUNCTION public.get_operational_workspace(text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_operational_workspace(text,integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
