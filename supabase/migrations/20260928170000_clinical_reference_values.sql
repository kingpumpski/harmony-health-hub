-- Ghana-aligned clinical reference-value control plane for user-facing vital-sign guidance.
-- References are effective-dated, source-attributed and review-due after 24 months.
CREATE TABLE IF NOT EXISTS public.clinical_reference_values (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parameter text NOT NULL,
  population_scope text NOT NULL DEFAULT 'adult',
  source_name text NOT NULL,
  source_reference text NOT NULL,
  source_url text NOT NULL,
  source_is_ghana_specific boolean NOT NULL DEFAULT false,
  effective_date date NOT NULL,
  normal_min numeric,
  normal_max numeric,
  thresholds jsonb NOT NULL DEFAULT '{}'::jsonb,
  display_text text NOT NULL,
  last_reviewed_at timestamptz NOT NULL DEFAULT now(),
  review_due_at timestamptz GENERATED ALWAYS AS (last_reviewed_at + interval '24 months') STORED,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  updated_by uuid REFERENCES auth.users(id),
  CONSTRAINT clinical_reference_source_name_chk CHECK (length(trim(source_name)) > 0),
  CONSTRAINT clinical_reference_source_url_chk CHECK (source_url ~* '^https?://'),
  CONSTRAINT clinical_reference_source_reference_chk CHECK (length(trim(source_reference)) > 0),
  CONSTRAINT clinical_reference_display_text_chk CHECK (length(trim(display_text)) > 0),
  CONSTRAINT clinical_reference_range_chk CHECK (
    normal_min IS NULL OR normal_max IS NULL OR normal_min <= normal_max
  ),
  CONSTRAINT clinical_reference_parameter_chk CHECK (parameter ~ '^[a-z][a-z0-9_]*$')
);

CREATE UNIQUE INDEX IF NOT EXISTS clinical_reference_active_parameter_scope_idx
  ON public.clinical_reference_values(parameter, population_scope)
  WHERE is_active;

ALTER TABLE public.clinical_reference_values ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS clinical_reference_read ON public.clinical_reference_values;
CREATE POLICY clinical_reference_read
  ON public.clinical_reference_values
  FOR SELECT TO authenticated
  USING (is_active = true OR public.has_role((select auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS clinical_reference_admin_insert ON public.clinical_reference_values;
CREATE POLICY clinical_reference_admin_insert
  ON public.clinical_reference_values
  FOR INSERT TO authenticated
  WITH CHECK (public.has_role((select auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS clinical_reference_admin_update ON public.clinical_reference_values;
CREATE POLICY clinical_reference_admin_update
  ON public.clinical_reference_values
  FOR UPDATE TO authenticated
  USING (public.has_role((select auth.uid()), 'admin'::app_role))
  WITH CHECK (public.has_role((select auth.uid()), 'admin'::app_role));

REVOKE ALL ON public.clinical_reference_values FROM anon;
GRANT SELECT ON public.clinical_reference_values TO authenticated;
GRANT INSERT, UPDATE ON public.clinical_reference_values TO authenticated;

INSERT INTO public.clinical_reference_values
(parameter, population_scope, source_name, source_reference, source_url, source_is_ghana_specific, effective_date, normal_min, normal_max, thresholds, display_text, last_reviewed_at)
VALUES
('blood_pressure_systolic','adult','Ghana Ministry of Health (MOH)','Standard Treatment Guideline, 2010','https://www.moh.gov.gh/wp-content/uploads/2016/02/Standard-Treatment-Guideline-2010.pdf',true,'2010-01-01',NULL,NULL,'{"hypertension_control":"<140/90 mmHg","diabetes_control":"<130/80 mmHg"}','BP control target: <140/90 mmHg for hypertension; <130/80 mmHg with diabetes.','2026-09-28T00:00:00Z'),
('blood_pressure_diastolic','adult','Ghana Ministry of Health (MOH)','Standard Treatment Guideline, 2010','https://www.moh.gov.gh/wp-content/uploads/2016/02/Standard-Treatment-Guideline-2010.pdf',true,'2010-01-01',NULL,NULL,'{"hypertension_control":"<140/90 mmHg","diabetes_control":"<130/80 mmHg"}','BP control target: <140/90 mmHg for hypertension; <130/80 mmHg with diabetes.','2026-09-28T00:00:00Z'),
('blood_pressure_combined','adult','Ghana Ministry of Health (MOH)','Standard Treatment Guideline, 2010','https://www.moh.gov.gh/wp-content/uploads/2016/02/Standard-Treatment-Guideline-2010.pdf',true,'2010-01-01',NULL,NULL,'{"hypertension_control":"<140/90 mmHg","diabetes_control":"<130/80 mmHg"}','BP control target: <140/90 mmHg for hypertension; <130/80 mmHg with diabetes. Interpret systolic and diastolic components together.','2026-09-28T00:00:00Z'),
('body_temperature','adult','Ghana Health Service (GHS) / Ministry of Health (MOH)','Guidelines for Case Management of Malaria in Ghana, 4th Edition, 2020','https://ghs.gov.gh/api/media/file/GUIDELINES_FOR_CASE_MANAGEMENT_OF_MALARIA.pdf',true,'2020-03-01',NULL,NULL,'{"axillary_or_infrared_fever_gte_c":37.5,"core_or_rectal_fever_gte_c":38.5}','Fever reference: axillary/infrared ≥37.5°C; core/rectal ≥38.5°C.','2026-09-28T00:00:00Z'),
('spo2','adult','World Health Organization (WHO)','WHO Pulse Oximetry Training Manual; Clinical Care for Severe Acute Respiratory Infection—Toolkit','https://cdn.who.int/media/docs/default-source/patient-safety/pulse-oximetry/who-ps-pulse-oxymetry-training-manual-en.pdf',false,'2011-01-01',95,100,'{"oxygen_therapy_threshold_percent":"<90"}','Typical adult SpO₂ reference: 95–100%. SpO₂ <90% requires urgent clinical assessment and oxygen therapy according to the applicable clinical protocol.','2026-09-28T00:00:00Z'),
('heart_rate','adult','World Health Organization (WHO) / ICRC','Basic Emergency Care: Approach to the Acutely Ill and Injured','https://www.who.int/publications/i/item/9789241513081',false,'2018-10-30',60,100,'{}','Normal adult pulse reference: 60–100 beats per minute.','2026-09-28T00:00:00Z'),
('respiratory_rate','adult','World Health Organization (WHO) / ICRC','Basic Emergency Care: Approach to the Acutely Ill and Injured','https://www.who.int/publications/i/item/9789241513081',false,'2018-10-30',10,20,'{}','Normal adult respiratory-rate reference: 10–20 breaths per minute.','2026-09-28T00:00:00Z'),
('pain_score','all_ages','World Health Organization (WHO)','WHO Emergency Unit Form: General','https://cdn.who.int/media/docs/default-source/documents/emergency-care/who-standardized-emergency-unit-form-general.pdf',false,'2019-01-01',0,10,'{}','Pain score uses a 0–10 numeric scale: 0 no pain; 10 worst pain.','2026-09-28T00:00:00Z')
ON CONFLICT (parameter, population_scope) WHERE is_active DO UPDATE SET
  source_name=excluded.source_name,
  source_reference=excluded.source_reference,
  source_url=excluded.source_url,
  source_is_ghana_specific=excluded.source_is_ghana_specific,
  effective_date=excluded.effective_date,
  normal_min=excluded.normal_min,
  normal_max=excluded.normal_max,
  thresholds=excluded.thresholds,
  display_text=excluded.display_text,
  last_reviewed_at=excluded.last_reviewed_at,
  updated_at=now();

CREATE OR REPLACE FUNCTION public.clinical_reference_values_audit_stamp()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by = COALESCE(NEW.created_by, (select auth.uid()));
  END IF;
  NEW.updated_at = now();
  NEW.updated_by = (select auth.uid());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS clinical_reference_values_audit_stamp_trg ON public.clinical_reference_values;
CREATE TRIGGER clinical_reference_values_audit_stamp_trg
BEFORE INSERT OR UPDATE ON public.clinical_reference_values
FOR EACH ROW EXECUTE FUNCTION public.clinical_reference_values_audit_stamp();
