CREATE OR REPLACE FUNCTION public.sync_module_compatibility_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=public
AS $$
BEGIN
  IF TG_TABLE_NAME = 'appointments' THEN
    IF NEW.appointment_date IS NULL THEN NEW.appointment_date := NEW.scheduled_at; END IF;
    IF NEW.scheduled_at IS NULL THEN NEW.scheduled_at := NEW.appointment_date; END IF;
    IF NEW.provider_id IS NULL THEN NEW.provider_id := NEW.practitioner_id; END IF;
    IF NEW.practitioner_id IS NULL THEN NEW.practitioner_id := NEW.provider_id; END IF;
  ELSIF TG_TABLE_NAME = 'payments' THEN
    IF NEW.payment_method IS NULL THEN NEW.payment_method := NEW.method; END IF;
    IF NEW.method IS NULL THEN NEW.method := NEW.payment_method; END IF;
    IF NEW.paid_at IS NULL AND NEW.status = 'completed' THEN NEW.paid_at := COALESCE(NEW.created_at, now()); END IF;
  ELSIF TG_TABLE_NAME = 'prescriptions' THEN
    IF NEW.medication_name IS NULL THEN NEW.medication_name := NEW.medication; END IF;
    IF NEW.medication IS NULL THEN NEW.medication := NEW.medication_name; END IF;
  ELSIF TG_TABLE_NAME = 'report_generation_items' THEN
    IF NEW.report_definition_id IS NULL THEN NEW.report_definition_id := NEW.report_id; END IF;
    IF NEW.report_id IS NULL THEN NEW.report_id := NEW.report_definition_id; END IF;
  ELSIF TG_TABLE_NAME = 'report_generation_runs' THEN
    IF NEW.reporting_period_start IS NULL THEN NEW.reporting_period_start := NEW.period_start; END IF;
    IF NEW.period_start IS NULL THEN NEW.period_start := NEW.reporting_period_start; END IF;
    IF NEW.reporting_period_end IS NULL THEN NEW.reporting_period_end := NEW.period_end; END IF;
    IF NEW.period_end IS NULL THEN NEW.period_end := NEW.reporting_period_end; END IF;
  ELSIF TG_TABLE_NAME = 'report_submissions' THEN
    IF NEW.report_definition_id IS NULL THEN NEW.report_definition_id := NEW.report_id; END IF;
    IF NEW.report_id IS NULL THEN NEW.report_id := NEW.report_definition_id; END IF;
    IF NEW.reporting_period_start IS NULL THEN NEW.reporting_period_start := NEW.period_start; END IF;
    IF NEW.period_start IS NULL THEN NEW.period_start := NEW.reporting_period_start; END IF;
    IF NEW.reporting_period_end IS NULL THEN NEW.reporting_period_end := NEW.period_end; END IF;
    IF NEW.period_end IS NULL THEN NEW.period_end := NEW.reporting_period_end; END IF;
  ELSIF TG_TABLE_NAME = 'vital_signs' THEN
    IF NEW.weight IS NULL THEN NEW.weight := NEW.weight_kg; END IF;
    IF NEW.weight_kg IS NULL THEN NEW.weight_kg := NEW.weight; END IF;
    IF NEW.height IS NULL THEN NEW.height := NEW.height_cm; END IF;
    IF NEW.height_cm IS NULL THEN NEW.height_cm := NEW.height; END IF;
    IF NEW.entered_by IS NULL THEN NEW.entered_by := NEW.recorded_by; END IF;
    IF NEW.recorded_by IS NULL THEN NEW.recorded_by := NEW.entered_by; END IF;
    IF NEW.created_at IS NULL THEN NEW.created_at := COALESCE(NEW.recorded_at, now()); END IF;
    IF NEW.recorded_at IS NULL THEN NEW.recorded_at := NEW.created_at; END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_appointments_compatibility ON public.appointments;
CREATE TRIGGER trg_sync_appointments_compatibility BEFORE INSERT OR UPDATE ON public.appointments FOR EACH ROW EXECUTE FUNCTION public.sync_module_compatibility_columns();
DROP TRIGGER IF EXISTS trg_sync_payments_compatibility ON public.payments;
CREATE TRIGGER trg_sync_payments_compatibility BEFORE INSERT OR UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.sync_module_compatibility_columns();
DROP TRIGGER IF EXISTS trg_sync_prescriptions_compatibility ON public.prescriptions;
CREATE TRIGGER trg_sync_prescriptions_compatibility BEFORE INSERT OR UPDATE ON public.prescriptions FOR EACH ROW EXECUTE FUNCTION public.sync_module_compatibility_columns();
DROP TRIGGER IF EXISTS trg_sync_report_generation_items_compatibility ON public.report_generation_items;
CREATE TRIGGER trg_sync_report_generation_items_compatibility BEFORE INSERT OR UPDATE ON public.report_generation_items FOR EACH ROW EXECUTE FUNCTION public.sync_module_compatibility_columns();
DROP TRIGGER IF EXISTS trg_sync_report_generation_runs_compatibility ON public.report_generation_runs;
CREATE TRIGGER trg_sync_report_generation_runs_compatibility BEFORE INSERT OR UPDATE ON public.report_generation_runs FOR EACH ROW EXECUTE FUNCTION public.sync_module_compatibility_columns();
DROP TRIGGER IF EXISTS trg_sync_report_submissions_compatibility ON public.report_submissions;
CREATE TRIGGER trg_sync_report_submissions_compatibility BEFORE INSERT OR UPDATE ON public.report_submissions FOR EACH ROW EXECUTE FUNCTION public.sync_module_compatibility_columns();
DROP TRIGGER IF EXISTS trg_sync_vital_signs_compatibility ON public.vital_signs;
CREATE TRIGGER trg_sync_vital_signs_compatibility BEFORE INSERT OR UPDATE ON public.vital_signs FOR EACH ROW EXECUTE FUNCTION public.sync_module_compatibility_columns();

UPDATE public.appointments SET appointment_date = scheduled_at WHERE appointment_date IS NULL;
UPDATE public.appointments SET provider_id = practitioner_id WHERE provider_id IS NULL;
UPDATE public.payments SET payment_method = method WHERE payment_method IS NULL;
UPDATE public.prescriptions SET medication_name = medication WHERE medication_name IS NULL;
UPDATE public.report_generation_items SET report_definition_id = report_id WHERE report_definition_id IS NULL;
UPDATE public.report_generation_runs SET reporting_period_start = period_start WHERE reporting_period_start IS NULL;
UPDATE public.report_generation_runs SET reporting_period_end = period_end WHERE reporting_period_end IS NULL;
UPDATE public.report_submissions SET report_definition_id = report_id WHERE report_definition_id IS NULL;
UPDATE public.report_submissions SET reporting_period_start = period_start WHERE reporting_period_start IS NULL;
UPDATE public.report_submissions SET reporting_period_end = period_end WHERE reporting_period_end IS NULL;
UPDATE public.vital_signs SET weight = weight_kg WHERE weight IS NULL;
UPDATE public.vital_signs SET height = height_cm WHERE height IS NULL;
UPDATE public.vital_signs SET entered_by = recorded_by WHERE entered_by IS NULL;
UPDATE public.vital_signs SET created_at = recorded_at WHERE created_at IS NULL;

NOTIFY pgrst, 'reload schema';
