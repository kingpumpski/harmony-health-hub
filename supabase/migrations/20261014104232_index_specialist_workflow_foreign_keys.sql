-- Cover specialist-workflow foreign keys used by patient, encounter, and audit lookups.
-- These indexes improve joins and parent-row maintenance without changing clinical data.
BEGIN;

CREATE INDEX IF NOT EXISTS idx_dental_assessments_created_by
  ON public.dental_assessments (created_by);
CREATE INDEX IF NOT EXISTS idx_dental_assessments_patient_id
  ON public.dental_assessments (patient_id);

CREATE INDEX IF NOT EXISTS idx_dietary_assessments_created_by
  ON public.dietary_assessments (created_by);
CREATE INDEX IF NOT EXISTS idx_dietary_assessments_patient_id
  ON public.dietary_assessments (patient_id);

CREATE INDEX IF NOT EXISTS idx_dietary_meal_orders_created_by
  ON public.dietary_meal_orders (created_by);
CREATE INDEX IF NOT EXISTS idx_dietary_meal_orders_assessment_id
  ON public.dietary_meal_orders (dietary_assessment_id);
CREATE INDEX IF NOT EXISTS idx_dietary_meal_orders_encounter_id
  ON public.dietary_meal_orders (encounter_id);
CREATE INDEX IF NOT EXISTS idx_dietary_meal_orders_patient_id
  ON public.dietary_meal_orders (patient_id);

CREATE INDEX IF NOT EXISTS idx_ophthalmology_assessments_created_by
  ON public.ophthalmology_assessments (created_by);
CREATE INDEX IF NOT EXISTS idx_ophthalmology_assessments_patient_id
  ON public.ophthalmology_assessments (patient_id);

CREATE INDEX IF NOT EXISTS idx_physio_assessments_created_by
  ON public.physio_assessments (created_by);
CREATE INDEX IF NOT EXISTS idx_physio_assessments_patient_id
  ON public.physio_assessments (patient_id);

CREATE INDEX IF NOT EXISTS idx_physio_treatment_plans_assessment_id
  ON public.physio_treatment_plans (assessment_id);
CREATE INDEX IF NOT EXISTS idx_physio_treatment_plans_created_by
  ON public.physio_treatment_plans (created_by);
CREATE INDEX IF NOT EXISTS idx_physio_treatment_plans_initial_encounter_id
  ON public.physio_treatment_plans (initial_encounter_id);
CREATE INDEX IF NOT EXISTS idx_physio_treatment_plans_patient_id
  ON public.physio_treatment_plans (patient_id);

CREATE INDEX IF NOT EXISTS idx_specialist_review_sessions_appointment_id
  ON public.specialist_review_sessions (appointment_id);
CREATE INDEX IF NOT EXISTS idx_specialist_review_sessions_created_by
  ON public.specialist_review_sessions (created_by);
CREATE INDEX IF NOT EXISTS idx_specialist_review_sessions_encounter_id
  ON public.specialist_review_sessions (encounter_id);
CREATE INDEX IF NOT EXISTS idx_specialist_review_sessions_patient_id
  ON public.specialist_review_sessions (patient_id);

COMMIT;