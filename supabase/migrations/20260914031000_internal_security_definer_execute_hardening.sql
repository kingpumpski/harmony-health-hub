-- Keep trigger/scheduler-only SECURITY DEFINER functions out of the client execution surface.
-- These functions are invoked by database triggers or internal jobs, not application RPCs.
REVOKE EXECUTE ON FUNCTION public.audit_patient_change() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_due_medications() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.lock_overdue_medication_slots() FROM PUBLIC, anon, authenticated;
