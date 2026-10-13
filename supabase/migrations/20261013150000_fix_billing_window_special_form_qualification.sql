-- Repair invalid schema qualification of PostgreSQL special expressions in billing materialization.
-- Preserve the existing function body, privileges, and security attributes; change only the
-- special-form spellings that cannot be called as pg_catalog functions.
DO $migration$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(
    'public.prepare_patient_billable_items(uuid,timestamp with time zone,timestamp with time zone)'::pg_catalog.regprocedure
  )
  INTO v_definition;

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'Required billing materialization function is missing';
  END IF;

  IF pg_catalog.position('pg_catalog.coalesce(' IN v_definition) = 0
     OR pg_catalog.position('pg_catalog.greatest(' IN v_definition) = 0
     OR pg_catalog.position('pg_catalog.least(' IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Billing materialization function differs from the expected broken definition; review before applying';
  END IF;

  v_definition := pg_catalog.replace(v_definition, 'pg_catalog.coalesce(', 'COALESCE(');
  v_definition := pg_catalog.replace(v_definition, 'pg_catalog.greatest(', 'GREATEST(');
  v_definition := pg_catalog.replace(v_definition, 'pg_catalog.least(', 'LEAST(');

  EXECUTE v_definition;
END;
$migration$;
