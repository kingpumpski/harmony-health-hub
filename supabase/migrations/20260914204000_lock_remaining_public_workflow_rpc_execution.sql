-- Keep patient billing and fertility workflow mutations out of the anonymous/public execution surface.
REVOKE ALL ON FUNCTION public.prepare_patient_billable_items(UUID, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_patient_billable_items(UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;

REVOKE ALL ON FUNCTION public.create_fertility_cycle_workflow(UUID, TEXT, TEXT, DATE, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_fertility_cycle_workflow(UUID, TEXT, TEXT, DATE, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.record_fertility_monitoring_workflow(UUID, DATE, INTEGER, NUMERIC, NUMERIC, NUMERIC, NUMERIC, INTEGER, INTEGER, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_fertility_monitoring_workflow(UUID, DATE, INTEGER, NUMERIC, NUMERIC, NUMERIC, NUMERIC, INTEGER, INTEGER, NUMERIC, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.transition_fertility_cycle_workflow(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_fertility_cycle_workflow(UUID, TEXT, TEXT) TO authenticated;
