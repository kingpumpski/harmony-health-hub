-- Foundation for specialty-specific clinical documentation and treatment plans.
-- This migration intentionally does not change existing clinical rows or billing logic.
BEGIN;

CREATE TABLE IF NOT EXISTS public.physio_assessments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
  encounter_id uuid NOT NULL REFERENCES public.encounters(id) ON DELETE RESTRICT,
  facility_id uuid NOT NULL,
  assessment_type text NOT NULL DEFAULT 'initial' CHECK (assessment_type IN ('initial','review')),
  chief_complaint text,
  range_of_motion jsonb NOT NULL DEFAULT '{}'::jsonb,
  muscle_strength jsonb NOT NULL DEFAULT '{}'::jsonb,
  pain_scale smallint CHECK (pain_scale BETWEEN 1 AND 10),
  functional_goals text[] NOT NULL DEFAULT ARRAY[]::text[],
  treatment_plan text,
  progress_notes text,
  treatment_given text,
  next_session_date date,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(range_of_motion) = 'object'),
  CHECK (jsonb_typeof(muscle_strength) = 'object')
);

CREATE TABLE IF NOT EXISTS public.physio_treatment_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
  initial_encounter_id uuid NOT NULL REFERENCES public.encounters(id) ON DELETE RESTRICT,
  facility_id uuid NOT NULL,
  assessment_id uuid NOT NULL REFERENCES public.physio_assessments(id) ON DELETE RESTRICT,
  planned_sessions integer NOT NULL CHECK (planned_sessions BETWEEN 1 AND 100),
  completed_sessions integer NOT NULL DEFAULT 0 CHECK (completed_sessions >= 0 AND completed_sessions <= planned_sessions),
  start_date date NOT NULL DEFAULT CURRENT_DATE,
  target_end_date date,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','cancelled','on_hold')),
  package_service_code text,
  notes text,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (target_end_date IS NULL OR target_end_date >= start_date)
);

CREATE TABLE IF NOT EXISTS public.ophthalmology_assessments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
  encounter_id uuid NOT NULL REFERENCES public.encounters(id) ON DELETE RESTRICT,
  facility_id uuid NOT NULL,
  visual_acuity_left text,
  visual_acuity_right text,
  intraocular_pressure jsonb NOT NULL DEFAULT '{}'::jsonb,
  slit_lamp_findings text,
  fundoscopy_findings text,
  refraction jsonb NOT NULL DEFAULT '{}'::jsonb,
  specialized_test_orders jsonb NOT NULL DEFAULT '[]'::jsonb,
  post_op_review_due date,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(intraocular_pressure) = 'object'),
  CHECK (jsonb_typeof(refraction) = 'object'),
  CHECK (jsonb_typeof(specialized_test_orders) = 'array')
);

CREATE TABLE IF NOT EXISTS public.dental_assessments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
  encounter_id uuid NOT NULL REFERENCES public.encounters(id) ON DELETE RESTRICT,
  facility_id uuid NOT NULL,
  tooth_chart_system text NOT NULL DEFAULT 'FDI' CHECK (tooth_chart_system IN ('FDI','Universal')),
  tooth_chart_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  periodontal_status text,
  oral_hygiene_instructions text,
  procedures_performed jsonb NOT NULL DEFAULT '[]'::jsonb,
  pending_procedures jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(tooth_chart_data) = 'object'),
  CHECK (jsonb_typeof(procedures_performed) = 'array'),
  CHECK (jsonb_typeof(pending_procedures) = 'array')
);

CREATE TABLE IF NOT EXISTS public.dietary_assessments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
  encounter_id uuid NOT NULL REFERENCES public.encounters(id) ON DELETE RESTRICT,
  facility_id uuid NOT NULL,
  weight_kg numeric(7,2) CHECK (weight_kg > 0),
  height_cm numeric(7,2) CHECK (height_cm > 0),
  bmi numeric(6,2) CHECK (bmi > 0),
  waist_circumference_cm numeric(7,2) CHECK (waist_circumference_cm > 0),
  biochemical_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  clinical_assessment text,
  dietary_recall jsonb NOT NULL DEFAULT '[]'::jsonb,
  nutritional_diagnosis text,
  meal_plan jsonb NOT NULL DEFAULT '{}'::jsonb,
  meal_plan_review_due date,
  adherence_notes text,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(biochemical_data) = 'object'),
  CHECK (jsonb_typeof(dietary_recall) = 'array'),
  CHECK (jsonb_typeof(meal_plan) = 'object')
);

CREATE TABLE IF NOT EXISTS public.dietary_meal_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
  encounter_id uuid NOT NULL REFERENCES public.encounters(id) ON DELETE RESTRICT,
  dietary_assessment_id uuid NOT NULL REFERENCES public.dietary_assessments(id) ON DELETE RESTRICT,
  facility_id uuid NOT NULL,
  diet_code text NOT NULL,
  diet_name text NOT NULL,
  meal_plan jsonb NOT NULL DEFAULT '{}'::jsonb,
  effective_from date NOT NULL DEFAULT CURRENT_DATE,
  effective_until date,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused','completed','cancelled')),
  kitchen_acknowledged_at timestamptz,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (effective_until IS NULL OR effective_until >= effective_from),
  CHECK (jsonb_typeof(meal_plan) = 'object')
);

CREATE TABLE IF NOT EXISTS public.specialist_review_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  specialty text NOT NULL CHECK (specialty IN ('physiotherapy','ophthalmology','dental','dietetics')),
  patient_id uuid NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
  encounter_id uuid NOT NULL REFERENCES public.encounters(id) ON DELETE RESTRICT,
  facility_id uuid NOT NULL,
  source_assessment_id uuid NOT NULL,
  appointment_id uuid REFERENCES public.appointments(id) ON DELETE SET NULL,
  scheduled_for timestamptz,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','scheduled','completed','cancelled','overdue')),
  progress_notes text,
  review_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(review_data) = 'object')
);

ALTER TABLE public.service_tariffs
  ADD COLUMN IF NOT EXISTS specialty_category text,
  ADD COLUMN IF NOT EXISTS package_session_count integer,
  ADD COLUMN IF NOT EXISTS is_session_package boolean NOT NULL DEFAULT false;

ALTER TABLE public.service_tariffs
  DROP CONSTRAINT IF EXISTS service_tariffs_package_session_count_check;
ALTER TABLE public.service_tariffs
  ADD CONSTRAINT service_tariffs_package_session_count_check
  CHECK (
    (is_session_package = false AND package_session_count IS NULL)
    OR (is_session_package = true AND package_session_count BETWEEN 1 AND 100)
  );

CREATE INDEX IF NOT EXISTS idx_physio_assessments_patient_facility_created
  ON public.physio_assessments (facility_id, patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_physio_assessments_encounter
  ON public.physio_assessments (encounter_id);
CREATE INDEX IF NOT EXISTS idx_physio_treatment_plans_pending
  ON public.physio_treatment_plans (facility_id, status, target_end_date);
CREATE INDEX IF NOT EXISTS idx_ophthalmology_assessments_encounter
  ON public.ophthalmology_assessments (encounter_id);
CREATE INDEX IF NOT EXISTS idx_dental_assessments_encounter
  ON public.dental_assessments (encounter_id);
CREATE INDEX IF NOT EXISTS idx_dietary_assessments_encounter
  ON public.dietary_assessments (encounter_id);
CREATE INDEX IF NOT EXISTS idx_dietary_meal_orders_kitchen_queue
  ON public.dietary_meal_orders (facility_id, status, effective_from);
CREATE INDEX IF NOT EXISTS idx_specialist_review_sessions_due
  ON public.specialist_review_sessions (facility_id, specialty, status, scheduled_for);

DO $rls$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'physio_assessments',
    'physio_treatment_plans',
    'ophthalmology_assessments',
    'dental_assessments',
    'dietary_assessments',
    'dietary_meal_orders',
    'specialist_review_sessions'
  ]
  LOOP
    EXECUTE pg_catalog.format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_table);
    EXECUTE pg_catalog.format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon', v_table);
    EXECUTE pg_catalog.format('GRANT SELECT, INSERT, UPDATE ON TABLE public.%I TO authenticated', v_table);
  END LOOP;
END;
$rls$;

CREATE POLICY physio_assessments_facility_access ON public.physio_assessments
  FOR ALL TO authenticated
  USING (facility_id = (SELECT public.current_user_facility_id()) AND (
    (SELECT public.has_role((SELECT auth.uid()), 'physiotherapist'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ))
  WITH CHECK (facility_id = (SELECT public.current_user_facility_id()) AND (
    (SELECT public.has_role((SELECT auth.uid()), 'physiotherapist'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ));

CREATE POLICY physio_treatment_plans_facility_access ON public.physio_treatment_plans
  FOR ALL TO authenticated
  USING (facility_id = (SELECT public.current_user_facility_id()) AND (
    (SELECT public.has_role((SELECT auth.uid()), 'physiotherapist'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ))
  WITH CHECK (facility_id = (SELECT public.current_user_facility_id()) AND (
    (SELECT public.has_role((SELECT auth.uid()), 'physiotherapist'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ));

CREATE POLICY ophthalmology_assessments_facility_access ON public.ophthalmology_assessments
  FOR ALL TO authenticated
  USING (facility_id = (SELECT public.current_user_facility_id()) AND (
    (SELECT public.has_role((SELECT auth.uid()), 'ophthalmologist'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ))
  WITH CHECK (facility_id = (SELECT public.current_user_facility_id()) AND (
    (SELECT public.has_role((SELECT auth.uid()), 'ophthalmologist'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ));

CREATE POLICY dental_assessments_facility_access ON public.dental_assessments
  FOR ALL TO authenticated
  USING (facility_id = (SELECT public.current_user_facility_id()) AND (
    (SELECT public.has_role((SELECT auth.uid()), 'dentist'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ))
  WITH CHECK (facility_id = (SELECT public.current_user_facility_id()) AND (
    (SELECT public.has_role((SELECT auth.uid()), 'dentist'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ));

CREATE POLICY dietary_assessments_facility_access ON public.dietary_assessments
  FOR ALL TO authenticated
  USING (facility_id = (SELECT public.current_user_facility_id()) AND (
    (SELECT public.has_role((SELECT auth.uid()), 'dietician'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ))
  WITH CHECK (facility_id = (SELECT public.current_user_facility_id()) AND (
    (SELECT public.has_role((SELECT auth.uid()), 'dietician'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ));

CREATE POLICY dietary_meal_orders_facility_access ON public.dietary_meal_orders
  FOR ALL TO authenticated
  USING (facility_id = (SELECT public.current_user_facility_id()) AND (
    (SELECT public.has_role((SELECT auth.uid()), 'dietician'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'nurse'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ))
  WITH CHECK (facility_id = (SELECT public.current_user_facility_id()) AND (
    (SELECT public.has_role((SELECT auth.uid()), 'dietician'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'nurse'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ));

CREATE POLICY specialist_review_sessions_facility_access ON public.specialist_review_sessions
  FOR ALL TO authenticated
  USING (facility_id = (SELECT public.current_user_facility_id()) AND (
    (specialty = 'physiotherapy' AND (SELECT public.has_role((SELECT auth.uid()), 'physiotherapist'::public.app_role)))
    OR (specialty = 'ophthalmology' AND (SELECT public.has_role((SELECT auth.uid()), 'ophthalmologist'::public.app_role)))
    OR (specialty = 'dental' AND (SELECT public.has_role((SELECT auth.uid()), 'dentist'::public.app_role)))
    OR (specialty = 'dietetics' AND (SELECT public.has_role((SELECT auth.uid()), 'dietician'::public.app_role)))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ))
  WITH CHECK (facility_id = (SELECT public.current_user_facility_id()) AND (
    (specialty = 'physiotherapy' AND (SELECT public.has_role((SELECT auth.uid()), 'physiotherapist'::public.app_role)))
    OR (specialty = 'ophthalmology' AND (SELECT public.has_role((SELECT auth.uid()), 'ophthalmologist'::public.app_role)))
    OR (specialty = 'dental' AND (SELECT public.has_role((SELECT auth.uid()), 'dentist'::public.app_role)))
    OR (specialty = 'dietetics' AND (SELECT public.has_role((SELECT auth.uid()), 'dietician'::public.app_role)))
    OR (SELECT public.has_role((SELECT auth.uid()), 'admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'it_admin'::public.app_role))
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  ));


-- Allow authenticated clinical staff in the same active facility to read specialty records
-- as part of the unified medical record; write access remains specialty-role restricted.
DO $read_policy$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'physio_assessments',
    'physio_treatment_plans',
    'ophthalmology_assessments',
    'dental_assessments',
    'dietary_assessments',
    'dietary_meal_orders',
    'specialist_review_sessions'
  ]
  LOOP
    EXECUTE pg_catalog.format(
      'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (facility_id = (SELECT public.current_user_facility_id()) AND (SELECT public.current_user_is_clinical_staff()))',
      v_table || '_clinical_read',
      v_table
    );
  END LOOP;
END;
$read_policy$;

COMMIT;
