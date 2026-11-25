BEGIN;
SELECT plan(8);

SELECT ok(
  (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
   WHERE p.oid='public.get_maternity_workspace(integer,uuid)'::regprocedure)
   ILIKE '%current_user_facility_id%'
   AND (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
        WHERE p.oid='public.get_maternity_workspace(integer,uuid)'::regprocedure)
   ILIKE '%facility_id%',
  'maternity workspace resolves and enforces active facility context'
);

SELECT ok(
  (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
   WHERE p.oid='public.get_department_queue(text,integer)'::regprocedure)
   ILIKE '%current_user_facility_id%'
   AND (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
        WHERE p.oid='public.get_department_queue(text,integer)'::regprocedure)
   ILIKE '%q.facility_id%'
   AND (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
        WHERE p.oid='public.get_department_queue(text,integer)'::regprocedure)
   ILIKE '%so.facility_id%',
  'department queue enforces facility lineage across queue and service order'
);

SELECT ok(
  (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
   WHERE p.oid='public.get_pharmacy_workspace(integer)'::regprocedure)
   ILIKE '%v_platform_admin%'
   AND (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
        WHERE p.oid='public.get_pharmacy_workspace(integer)'::regprocedure)
   NOT ILIKE '%AND (v_admin OR (v_facility IS NOT NULL AND p.facility_id = v_facility))%',
  'pharmacy patient reads do not use facility-admin global bypass'
);

SELECT ok(
  (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
   WHERE p.oid='public.get_laboratory_workspace(integer)'::regprocedure)
   ILIKE '%current_user_facility_id%'
   AND (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
        WHERE p.oid='public.get_laboratory_workspace(integer)'::regprocedure)
   ILIKE '%facility_id%',
  'laboratory workspace resolves and applies active facility scope'
);

SELECT ok(
  (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
   WHERE p.oid='public.get_imaging_workspace(integer)'::regprocedure)
   ILIKE '%current_user_facility_id%'
   AND (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
        WHERE p.oid='public.get_imaging_workspace(integer)'::regprocedure)
   ILIKE '%facility_id%',
  'imaging workspace resolves and applies active facility scope'
);

SELECT ok(
  (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
   WHERE p.oid='public.get_canteen_active_patient_orders()'::regprocedure)
   ILIKE '%current_user_facility_id%'
   AND (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
        WHERE p.oid='public.get_canteen_active_patient_orders()'::regprocedure)
   ILIKE '%facility_id%',
  'canteen patient-order workspace is facility-scoped'
);

SELECT ok(
  (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
   WHERE p.oid='public.get_operational_workspace(text,integer)'::regprocedure)
   ILIKE '%v_facility IS NOT NULL%'
   AND (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
        WHERE p.oid='public.get_operational_workspace(text,integer)'::regprocedure)
   NOT ILIKE '%OR facility_id IS NULL%',
  'operational workspace fails closed for missing facility and excludes unassigned ward/bed rows'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='patient_audit_log'
      AND cmd='SELECT'
      AND (qual ILIKE '%facility%' OR qual ILIKE '%current_user_can_select_facility_record%')
  ),
  'patient audit log read policy includes facility boundary'
);

SELECT * FROM finish();
ROLLBACK;
