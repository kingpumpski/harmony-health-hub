-- Forward-only repair for billing materialization SQL special forms.
-- The historical correction migration may be absent from some ledgers. This repair is
-- safe whether the function is still broken or has already been corrected.
DO $migration$
DECLARE
  v_definition text;
  v_coalesce integer;
  v_greatest integer;
  v_least integer;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(
    'public.prepare_patient_billable_items(uuid,timestamp with time zone,timestamp with time zone)'::pg_catalog.regprocedure
  )
  INTO v_definition;

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'Required billing materialization function is missing';
  END IF;

  v_coalesce := pg_catalog.length(v_definition) - pg_catalog.length(pg_catalog.replace(v_definition, 'pg_catalog.coalesce(', ''));
  v_greatest := pg_catalog.length(v_definition) - pg_catalog.length(pg_catalog.replace(v_definition, 'pg_catalog.greatest(', ''));
  v_least := pg_catalog.length(v_definition) - pg_catalog.length(pg_catalog.replace(v_definition, 'pg_catalog.least(', ''));

  -- Already repaired: leave the function untouched.
  IF v_coalesce = 0 AND v_greatest = 0 AND v_least = 0 THEN
    RETURN;
  END IF;

  -- Partial or unexpected drift must be reviewed, not silently rewritten.
  IF v_coalesce = 0 OR v_greatest = 0 OR v_least = 0 THEN
    RAISE EXCEPTION
      'Billing materialization function has a partial/unexpected special-form qualification state (coalesce %, greatest %, least %); review before applying',
      v_coalesce, v_greatest, v_least;
  END IF;

  v_definition := pg_catalog.replace(v_definition, 'pg_catalog.coalesce(', 'COALESCE(');
  v_definition := pg_catalog.replace(v_definition, 'pg_catalog.greatest(', 'GREATEST(');
  v_definition := pg_catalog.replace(v_definition, 'pg_catalog.least(', 'LEAST(');

  EXECUTE v_definition;
END;
$migration$;
