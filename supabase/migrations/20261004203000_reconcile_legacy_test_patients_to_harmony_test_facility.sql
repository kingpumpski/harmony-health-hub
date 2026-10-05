-- One-time administrative reconciliation of the three legacy test patients.
-- These records were intentionally left unattributed pending Admin/IT Admin review.
-- The target is the active Harmony Health Hub Test Facility (TEST-0001).
-- Only the facility-assignment guard trigger is disabled for the atomic correction;
-- patient audit triggers remain enabled.
BEGIN;

ALTER TABLE public.patients DISABLE TRIGGER patients_assign_active_facility;

UPDATE public.patients
SET facility_id = '0d34d78b-1c01-4e5b-b760-bc60050b37aa',
    updated_at = now()
WHERE id IN (
  '7b37f2ac-1f3d-4444-82f5-b3abba3dec24',
  'd967f772-b8b2-4340-9a71-fe5eda3cbc7f',
  '33da50e6-ec5f-42f9-ba79-c46f8013b59d'
)
AND facility_id IS NULL;

ALTER TABLE public.patients ENABLE TRIGGER patients_assign_active_facility;

COMMIT;

NOTIFY pgrst, 'reload schema';