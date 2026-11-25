BEGIN;
SELECT plan(8);

-- Normalize whitespace so the assertions describe authorization semantics
-- rather than depending on the SQL formatter used by CREATE FUNCTION.
WITH f AS (
  SELECT regexp_replace(lower(pg_get_functiondef('public.get_maternity_workspace(integer,uuid)'::regprocedure)), '[[:space:]]+', '', 'g') AS d
)
SELECT ok(
  d LIKE '%current_user_facility_id%'
  AND d LIKE '%me.facility_id=v_facility%'
  AND d LIKE '%p.facility_id=v_facility%'
  AND d LIKE '%v_facilityisnull%',
  'maternity episode and patient reads require a resolved, matching active facility'
) FROM f;

WITH f AS (
  SELECT regexp_replace(lower(pg_get_functiondef('public.get_department_queue(text,integer)'::regprocedure)), '[[:space:]]+', '', 'g') AS d
)
SELECT ok(
  d LIKE '%current_user_facility_id%'
  AND d LIKE '%q.facility_id=v_facility%'
  AND d LIKE '%so.facility_id=v_facility%'
  AND d LIKE '%p.facility_id=v_facility%'
  AND d LIKE '%v_facilityisnull%',
  'department queue enforces facility lineage across queue, service order, and patient'
) FROM f;

WITH f AS (
  SELECT regexp_replace(lower(pg_get_functiondef('public.get_pharmacy_workspace(integer)'::regprocedure)), '[[:space:]]+', '', 'g') AS d
)
SELECT ok(
  d LIKE '%current_user_facility_id%'
  AND d LIKE '%v_superuser%'
  AND d LIKE '%v_facilityisnull%'
  AND d NOT LIKE '%v_adminor(v_facilityisnotnullandp.facility_id=v_facility)%'
  AND d NOT LIKE '%v_adminor(v_facilityisnotnullandd.facility_id=v_facility)%',
  'pharmacy patient and dispensing-plan reads do not treat facility admin as a platform-wide bypass'
) FROM f;

WITH f AS (
  SELECT regexp_replace(lower(pg_get_functiondef('public.get_laboratory_workspace(integer)'::regprocedure)), '[[:space:]]+', '', 'g') AS d
)
SELECT ok(
  d LIKE '%current_user_facility_id%'
  AND d LIKE '%p.facility_id=v_facility%'
  AND d LIKE '%o.facility_id=v_facility%'
  AND d LIKE '%r.facility_id=v_facility%',
  'laboratory patient, order, and result reads share the active facility boundary'
) FROM f;

WITH f AS (
  SELECT regexp_replace(lower(pg_get_functiondef('public.get_imaging_workspace(integer)'::regprocedure)), '[[:space:]]+', '', 'g') AS d
)
SELECT ok(
  d LIKE '%current_user_facility_id%'
  AND d LIKE '%p.facility_id=v_facility%'
  AND d LIKE '%io.facility_id=v_facility%',
  'imaging patient and imaging-order reads share the active facility boundary'
) FROM f;

WITH f AS (
  SELECT regexp_replace(lower(pg_get_functiondef('public.get_canteen_active_patient_orders()'::regprocedure)), '[[:space:]]+', '', 'g') AS d
)
SELECT ok(
  d LIKE '%current_user_facility_id%'
  AND d LIKE '%mo.facility_id=v_facility%'
  AND d LIKE '%p.facility_id=v_facility%'
  AND d LIKE '%mp.facility_id=v_facility%',
  'canteen patient orders and linked meal plans are facility-scoped'
) FROM f;

WITH f AS (
  SELECT regexp_replace(lower(pg_get_functiondef('public.get_operational_workspace(text,integer)'::regprocedure)), '[[:space:]]+', '', 'g') AS d
)
SELECT ok(
  d LIKE '%current_user_facility_id%'
  AND d LIKE '%v_platform_admin%'
  AND d NOT LIKE '%orv_facilityisnull%'
  AND d NOT LIKE '%facility_idisnull%'
  AND d LIKE '%p.facility_id=v_facility%'
  AND d LIKE '%facility_id=v_facility%',
  'operational workspace fails closed for missing facility and does not expose unassigned ward or bed rows'
) FROM f;

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='patient_audit_log'
      AND cmd='SELECT'
      AND qual ILIKE '%current_user_facility_id%'
      AND qual ILIKE '%patient_id%'
      AND qual ILIKE '%patients%'
      AND qual ILIKE '%exists%'
      AND qual ILIKE '%facility_id%'
  ),
  'patient audit log read policy requires patient lineage and active facility authorization'
);

SELECT * FROM finish();
ROLLBACK;
