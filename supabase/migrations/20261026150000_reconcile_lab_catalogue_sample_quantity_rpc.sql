BEGIN;

-- Legacy installations created sample_quantity as numeric. The current UI accepts
-- quantities with units (for example "5 ml"), so reconcile it to text without
-- discarding existing numeric values.
DO $sample_quantity_type$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'lab_test_catalogue'
      AND column_name = 'sample_quantity'
      AND data_type <> 'text'
  ) THEN
    ALTER TABLE public.lab_test_catalogue
      ALTER COLUMN sample_quantity TYPE text
      USING sample_quantity::text;
  END IF;
END;
$sample_quantity_type$;

-- Keep the legacy client RPC name and exact argument names used by PostgREST.
CREATE OR REPLACE FUNCTION public.create_lab_test_catalogue_item_with_sample_quantity(
  _test_code text,
  _test_name text,
  _category text,
  _specimen_type text,
  _sample_quantity text,
  _unit text,
  _reference_low numeric,
  _reference_high numeric,
  _reference_text text,
  _default_charge numeric,
  _turnaround_minutes integer,
  _parameters jsonb DEFAULT '[]'::jsonb
)
RETURNS public.lab_test_catalogue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  r public.lab_test_catalogue;
BEGIN
  r := public.create_lab_test_catalogue_item_with_parameters(
    _test_code,
    _test_name,
    _category,
    _specimen_type,
    _unit,
    _reference_low,
    _reference_high,
    _reference_text,
    _default_charge,
    _turnaround_minutes,
    coalesce(_parameters, '[]'::jsonb)
  );

  UPDATE public.lab_test_catalogue
  SET sample_quantity = nullif(pg_catalog.btrim(coalesce(_sample_quantity, '')), ''),
      updated_at = now()
  WHERE id = r.id
  RETURNING * INTO r;

  PERFORM public.record_system_audit(
    'lab_test_catalogue_sample_quantity_set',
    'laboratory',
    'lab_test_catalogue',
    r.id,
    'info',
    jsonb_build_object('test_code', r.test_code, 'sample_quantity', r.sample_quantity)
  );

  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_lab_test_catalogue_item_with_sample_quantity(
  text,text,text,text,text,text,numeric,numeric,text,numeric,integer,jsonb
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_lab_test_catalogue_item_with_sample_quantity(
  text,text,text,text,text,text,numeric,numeric,text,numeric,integer,jsonb
) TO authenticated;

COMMIT;
