-- Add covering indexes for the remaining foreign keys identified by Supabase performance advisors.
CREATE INDEX IF NOT EXISTS hms_test_runtime_audit_changed_by_idx ON public.hms_test_runtime_audit(changed_by);
CREATE INDEX IF NOT EXISTS imaging_orders_acknowledged_by_idx ON public.imaging_orders(acknowledged_by);
CREATE INDEX IF NOT EXISTS lab_results_acknowledged_by_idx ON public.lab_results(acknowledged_by);
CREATE INDEX IF NOT EXISTS medication_catalogue_created_by_idx ON public.medication_catalogue(created_by);
