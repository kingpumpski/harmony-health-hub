-- Reapply the canonical row-audit trigger to operational tables created after the
-- initial generic audit migration. Audit infrastructure itself remains excluded.
DO $do$
DECLARE r record;
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

NOTIFY pgrst, 'reload schema';
