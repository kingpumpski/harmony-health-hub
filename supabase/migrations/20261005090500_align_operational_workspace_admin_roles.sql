-- Extend the existing operational workspace read surface for platform/facility administrators.
DO $migration$
DECLARE src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO src
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='get_operational_workspace'
    AND pg_get_function_identity_arguments(p.oid)='_module text, _limit integer';
  IF src IS NULL THEN RAISE EXCEPTION 'get_operational_workspace(text,integer) was not found'; END IF;

  src := replace(src,
    'IF v_role NOT IN (''admin'',''practitioner'',''nurse'',''midwife'',''specialist_nurse'') THEN RAISE EXCEPTION ''Not authorised''; END IF;',
    'IF v_role NOT IN (''admin'',''it_admin'',''system_superuser'',''practitioner'',''nurse'',''midwife'',''specialist_nurse'') THEN RAISE EXCEPTION ''Not authorised''; END IF;'
  );
  src := replace(src,
    'WHERE v_role=''admin'' OR facility_id IS NULL OR facility_id=v_facility',
    'WHERE v_role IN (''admin'',''it_admin'',''system_superuser'') OR facility_id IS NULL OR facility_id=v_facility'
  );
  src := replace(src,
    'WHERE v_role=''admin'' OR b.facility_id IS NULL OR b.facility_id=v_facility',
    'WHERE v_role IN (''admin'',''it_admin'',''system_superuser'') OR b.facility_id IS NULL OR b.facility_id=v_facility'
  );
  EXECUTE src;
END
$migration$;

REVOKE ALL ON FUNCTION public.get_operational_workspace(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_operational_workspace(text,integer) TO authenticated;