-- Converge high-value clinical workflow mutations with the existing
-- append-only system audit boundary. No new audit subsystem is introduced.
-- The existing audit trigger function is reused across the major clinical
-- workflow domains so next-generation safety boundaries share one audit surface.

DO $$
DECLARE
  table_name TEXT;
  trigger_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'appointments',
    'medication_administrations',
    'lab_orders',
    'lab_results',
    'imaging_orders',
    'insurance_claims'
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

COMMENT ON TABLE public.appointments IS
  'Appointment lifecycle is server-authoritative through authenticated workflow RPCs and converged clinical audit.';

COMMENT ON TABLE public.medication_administrations IS
  'Medication administration lifecycle is server-authoritative through authenticated clinical RPCs and converged clinical audit.';

COMMENT ON TABLE public.lab_orders IS
  'Laboratory order lifecycle is server-authoritative through authenticated workflow RPCs and converged clinical audit.';

COMMENT ON TABLE public.lab_results IS
  'Laboratory result lifecycle is server-authoritative through authenticated workflow RPCs and converged clinical audit.';

COMMENT ON TABLE public.imaging_orders IS
  'Imaging lifecycle is server-authoritative through authenticated workflow RPCs and converged clinical audit.';

COMMENT ON TABLE public.insurance_claims IS
  'Insurance claim lifecycle and financial changes are server-authoritative through authenticated workflow RPCs and converged clinical audit.';
