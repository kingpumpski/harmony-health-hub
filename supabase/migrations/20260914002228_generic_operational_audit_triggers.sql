-- Centralized operational traceability for row mutations.
-- Each row already has a primary identifier; this migration makes those identifiers
-- consistently traceable through system_audit_log without copying sensitive row values.

CREATE OR REPLACE FUNCTION public.audit_operational_row_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_row jsonb;
  v_entity_id uuid;
  v_entity_key text;
  v_changed_columns jsonb := '[]'::jsonb;
  v_actor uuid;
BEGIN
  v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  v_entity_key := v_row ->> 'id';

  BEGIN
    v_entity_id := NULLIF(v_entity_key, '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    v_entity_id := NULL;
  END;

  v_actor := auth.uid();

  IF TG_OP = 'UPDATE' THEN
    SELECT COALESCE(jsonb_agg(key ORDER BY key), '[]'::jsonb)
      INTO v_changed_columns
      FROM (
        SELECT COALESCE(o.key, n.key) AS key
        FROM jsonb_each(to_jsonb(OLD)) o
        FULL JOIN jsonb_each(to_jsonb(NEW)) n ON n.key = o.key
        WHERE o.value IS DISTINCT FROM n.value
      ) changed;
  END IF;

  INSERT INTO public.system_audit_log (
    actor_id,
    action,
    module,
    entity_type,
    entity_id,
    severity,
    metadata
  )
  VALUES (
    v_actor,
    lower(TG_OP),
    TG_TABLE_NAME,
    TG_TABLE_NAME,
    v_entity_id,
    'info',
    jsonb_build_object(
      'entity_key', v_entity_key,
      'operation', TG_OP,
      'changed_columns', v_changed_columns,
      'audit_source', 'row_trigger'
    )
  );

  RETURN COALESCE(NEW, OLD);
END;
$function$;

DO $do$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public'
      AND c.relkind='r'
      AND c.relname NOT IN ('system_audit_log','patient_audit')
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS audit_operational_row_change ON public.%I', r.table_name);
    EXECUTE format(
      'CREATE TRIGGER audit_operational_row_change AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.audit_operational_row_change()',
      r.table_name
    );
  END LOOP;
END
$do$;

REVOKE EXECUTE ON FUNCTION public.audit_operational_row_change() FROM PUBLIC, anon, authenticated;
NOTIFY pgrst, 'reload schema';
