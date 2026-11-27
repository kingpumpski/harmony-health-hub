-- Complete the four documented cross-module FK gaps without deleting clinical history.
-- Preflight rejects unexpected orphans rather than silently dropping or rewriting records.
BEGIN;

DO $preflight$
DECLARE
  orphan_count bigint;
BEGIN
  SELECT count(*) INTO orphan_count
  FROM public.emergency_cases e
  LEFT JOIN public.patients p ON p.id = e.patient_id
  WHERE e.patient_id IS NOT NULL AND p.id IS NULL;
  IF orphan_count > 0 THEN
    RAISE EXCEPTION 'emergency_cases.patient_id has % orphan reference(s); reconcile records before adding FK', orphan_count;
  END IF;

  SELECT count(*) INTO orphan_count
  FROM public.transfusion_records t
  LEFT JOIN public.patients p ON p.id = t.patient_id
  WHERE t.patient_id IS NOT NULL AND p.id IS NULL;
  IF orphan_count > 0 THEN
    RAISE EXCEPTION 'transfusion_records.patient_id has % orphan reference(s); preserve transfusion history and reconcile before adding FK', orphan_count;
  END IF;

  SELECT count(*) INTO orphan_count
  FROM public.medication_administrations m
  LEFT JOIN public.prescriptions p ON p.id = m.prescription_id
  WHERE m.prescription_id IS NOT NULL AND p.id IS NULL;
  IF orphan_count > 0 THEN
    RAISE EXCEPTION 'medication_administrations.prescription_id has % orphan reference(s); reconcile medication history before adding FK', orphan_count;
  END IF;

  SELECT count(*) INTO orphan_count
  FROM public.ward_beds b
  LEFT JOIN public.admissions a ON a.id = b.admission_id
  WHERE b.admission_id IS NOT NULL AND a.id IS NULL;
  IF orphan_count > 0 THEN
    RAISE EXCEPTION 'ward_beds.admission_id has % orphan reference(s); reconcile bed occupancy before adding FK', orphan_count;
  END IF;
END;
$preflight$;

DO $constraints$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.emergency_cases'::regclass AND conname='emergency_cases_patient_id_fkey') THEN
    ALTER TABLE public.emergency_cases
      ADD CONSTRAINT emergency_cases_patient_id_fkey
      FOREIGN KEY (patient_id) REFERENCES public.patients(id)
      ON DELETE SET NULL NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.transfusion_records'::regclass AND conname='transfusion_records_patient_id_fkey') THEN
    ALTER TABLE public.transfusion_records
      ADD CONSTRAINT transfusion_records_patient_id_fkey
      FOREIGN KEY (patient_id) REFERENCES public.patients(id)
      ON DELETE RESTRICT NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.medication_administrations'::regclass AND conname='medication_administrations_prescription_id_fkey') THEN
    ALTER TABLE public.medication_administrations
      ADD CONSTRAINT medication_administrations_prescription_id_fkey
      FOREIGN KEY (prescription_id) REFERENCES public.prescriptions(id)
      ON DELETE SET NULL NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.ward_beds'::regclass AND conname='ward_beds_admission_id_fkey') THEN
    ALTER TABLE public.ward_beds
      ADD CONSTRAINT ward_beds_admission_id_fkey
      FOREIGN KEY (admission_id) REFERENCES public.admissions(id)
      ON DELETE RESTRICT NOT VALID;
  END IF;
END;
$constraints$;

ALTER TABLE public.emergency_cases VALIDATE CONSTRAINT emergency_cases_patient_id_fkey;
ALTER TABLE public.transfusion_records VALIDATE CONSTRAINT transfusion_records_patient_id_fkey;
ALTER TABLE public.medication_administrations VALIDATE CONSTRAINT medication_administrations_prescription_id_fkey;
ALTER TABLE public.ward_beds VALIDATE CONSTRAINT ward_beds_admission_id_fkey;

CREATE INDEX IF NOT EXISTS idx_emergency_cases_patient_id_fk
  ON public.emergency_cases(patient_id);
CREATE INDEX IF NOT EXISTS idx_transfusion_records_patient_id_fk
  ON public.transfusion_records(patient_id);
CREATE INDEX IF NOT EXISTS idx_medication_administrations_prescription_id_fk
  ON public.medication_administrations(prescription_id);
CREATE INDEX IF NOT EXISTS idx_ward_beds_admission_id_fk
  ON public.ward_beds(admission_id);

NOTIFY pgrst, 'reload schema';
COMMIT;
