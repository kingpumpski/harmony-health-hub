BEGIN;

-- Keep the dedicated test facility usable without reclassifying historical
-- patients whose facility attribution is missing or belongs to another site.
-- This fixture is clearly synthetic and is inserted only into TEST-0001.
ALTER TABLE public.patients DISABLE TRIGGER patients_assign_active_facility;

INSERT INTO public.patients (
  patient_code,
  first_name,
  last_name,
  date_of_birth,
  gender,
  membership_type,
  registration_reason,
  status,
  facility_id
)
SELECT
  'TEST-DEMO-0001',
  'Harmony Test',
  'Patient',
  DATE '1990-01-01',
  'other',
  'permanent',
  'Synthetic QA fixture only. Not a real patient; use only in TEST-0001.',
  'active',
  hf.id
FROM public.healthcare_facilities hf
WHERE hf.facility_code = 'TEST-0001'
  AND hf.is_active = true
  AND NOT EXISTS (
    SELECT 1 FROM public.patients p WHERE p.patient_code = 'TEST-DEMO-0001'
  )
ORDER BY hf.id
LIMIT 1
ON CONFLICT (patient_code) DO NOTHING;

ALTER TABLE public.patients ENABLE TRIGGER patients_assign_active_facility;

COMMIT;
