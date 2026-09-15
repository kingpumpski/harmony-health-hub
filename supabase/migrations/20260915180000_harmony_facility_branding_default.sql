-- Keep the canonical facility default aligned with Harmony Health Hub branding.
-- This is a forward-only migration; the historical seed migration remains immutable.
ALTER TABLE public.facility_settings
  ALTER COLUMN facility_name SET DEFAULT 'Harmony Health Hub';

-- Normalize the canonical singleton when it still carries the legacy seed value.
-- Do not overwrite an administrator-configured facility name.
UPDATE public.facility_settings
SET facility_name = 'Harmony Health Hub',
    updated_at = now()
WHERE id = 'default'
  AND facility_name = 'MediCare Pro Hospital';
