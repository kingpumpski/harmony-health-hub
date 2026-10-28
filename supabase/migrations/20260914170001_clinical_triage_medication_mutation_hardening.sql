-- Route triage and medication-administration state changes through authenticated lifecycle RPCs.
REVOKE INSERT, UPDATE, DELETE ON public.triage_assessments FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.medication_administrations FROM authenticated;

REVOKE ALL ON FUNCTION public.record_triage_assessment(UUID, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_triage_assessment(UUID, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.schedule_medication_administration(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schedule_medication_administration(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.transition_medication_administration(UUID, TEXT, TEXT, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_medication_administration(UUID, TEXT, TEXT, TEXT, UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.reopen_medication_administration(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reopen_medication_administration(UUID, TEXT) TO authenticated;
