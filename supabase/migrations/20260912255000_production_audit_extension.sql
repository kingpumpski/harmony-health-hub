-- Production audit extension for newly hardened modules.

DO $$
DECLARE
  table_name TEXT;
  trigger_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'video_sessions',
    'ophthalmology_exams'
  ] LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL
       AND to_regprocedure('public.audit_clinical_record_change()') IS NOT NULL THEN
      trigger_name := 'trg_audit_' || table_name || '_changes';
      EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', trigger_name, table_name);
      EXECUTE format(
        'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.audit_clinical_record_change()',
        trigger_name,
        table_name
      );
    END IF;
  END LOOP;
END;
$$;
