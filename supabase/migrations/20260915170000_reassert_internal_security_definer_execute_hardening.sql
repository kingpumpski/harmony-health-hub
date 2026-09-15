-- Reassert the intended client-execution boundary for internal SECURITY DEFINER routines.
--
-- Earlier medication migrations granted authenticated execution to the reminder/lock
-- routines because they were temporarily invoked by the MAR screen. The later
-- security boundary intentionally made these routines trigger/scheduler-only.
-- This migration is idempotent and makes the final privilege state explicit after
-- any function replacement/reconciliation.
REVOKE EXECUTE ON FUNCTION public.audit_patient_change() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_due_medications() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.lock_overdue_medication_slots() FROM PUBLIC, anon, authenticated;

-- Keep the existing authenticated execution surface for the actual application RPCs;
-- this migration deliberately does not revoke workflow functions used by the UI.
