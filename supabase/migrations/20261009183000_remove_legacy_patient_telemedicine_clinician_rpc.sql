-- Remove the obsolete zero-argument overload left by earlier patient portal migrations.
-- The supported client contract supplies _scheduled_at and must resolve to the
-- shift-aware, facility-scoped function defined in 20261008170000.
BEGIN;

DROP FUNCTION IF EXISTS public.get_patient_telemedicine_clinicians();

NOTIFY pgrst, 'reload schema';

COMMIT;
