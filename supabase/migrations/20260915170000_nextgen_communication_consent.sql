-- Explicit emergency communication override consent is a patient preference,
-- not an implicit bypass of channel or minimum-necessary controls.
ALTER TABLE public.patient_communication_preferences
  ADD COLUMN IF NOT EXISTS emergency_override_allowed BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.patient_communication_preferences.emergency_override_allowed IS
  'Explicit patient consent for emergency communication to use a non-preferred channel when clinically necessary; minimum-necessary disclosure remains mandatory.';
