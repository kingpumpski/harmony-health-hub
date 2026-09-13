-- Reports Center foundation: facility-aware, configuration-driven public-health reporting.
-- Deliberately avoids executable SQL query templates. Report extraction is selected by
-- stable extractor_key values in the application/report engine so report definitions
-- cannot become an arbitrary SQL execution surface.

CREATE TABLE IF NOT EXISTS public.healthcare_facilities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  facility_code TEXT UNIQUE,
  facility_type TEXT NOT NULL CHECK (facility_type IN (
    'chps_compound','health_centre','district_hospital','regional_hospital',
    'teaching_hospital','hiv_clinic','maternity_home','specialist_clinic','other'
  )),
  district TEXT,
  region TEXT,
  dhims2_uid TEXT UNIQUE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.facility_memberships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id UUID NOT NULL REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  access_scope TEXT NOT NULL DEFAULT 'facility' CHECK (access_scope IN ('facility','district','regional','national')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (facility_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_facility_memberships_user ON public.facility_memberships(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_facility_memberships_facility ON public.facility_memberships(facility_id, is_active);

CREATE TABLE IF NOT EXISTS public.report_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  display_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.report_definitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_code TEXT NOT NULL UNIQUE,
  report_name TEXT NOT NULL,
  category_id UUID REFERENCES public.report_categories(id) ON DELETE SET NULL,
  description TEXT,
  frequency TEXT NOT NULL DEFAULT 'monthly' CHECK (frequency IN ('weekly','monthly','quarterly','annual')),
  parameters JSONB NOT NULL DEFAULT '[]'::jsonb,
  default_parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
  extractor_key TEXT NOT NULL,
  supported_formats TEXT[] NOT NULL DEFAULT ARRAY['xlsx','csv'],
  submission_deadline_day INTEGER NOT NULL DEFAULT 5 CHECK (submission_deadline_day BETWEEN 1 AND 28),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  implementation_status TEXT NOT NULL DEFAULT 'seeded' CHECK (implementation_status IN ('seeded','mapped','validated','retired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.facility_report_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id UUID NOT NULL REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  report_id UUID NOT NULL REFERENCES public.report_definitions(id) ON DELETE CASCADE,
  is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  submission_deadline_day INTEGER CHECK (submission_deadline_day BETWEEN 1 AND 28),
  custom_parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (facility_id, report_id)
);

CREATE INDEX IF NOT EXISTS idx_facility_report_config_enabled ON public.facility_report_config(facility_id, is_enabled);

CREATE TABLE IF NOT EXISTS public.report_generation_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id UUID NOT NULL REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  frequency TEXT NOT NULL DEFAULT 'monthly' CHECK (frequency IN ('weekly','monthly','quarterly','annual')),
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','processing','completed','partial_failed','failed','cancelled')),
  total_reports INTEGER NOT NULL DEFAULT 0,
  success_count INTEGER NOT NULL DEFAULT 0,
  warning_count INTEGER NOT NULL DEFAULT 0,
  failed_count INTEGER NOT NULL DEFAULT 0,
  parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
  bundle_manifest JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_report_generation_runs_facility_period ON public.report_generation_runs(facility_id, period_start, period_end);

CREATE TABLE IF NOT EXISTS public.report_generation_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES public.report_generation_runs(id) ON DELETE CASCADE,
  report_id UUID NOT NULL REFERENCES public.report_definitions(id) ON DELETE RESTRICT,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','processing','completed','failed','warning')),
  output_format TEXT NOT NULL DEFAULT 'xlsx' CHECK (output_format IN ('xlsx','csv','pdf')),
  file_name TEXT,
  data_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  validation_messages JSONB NOT NULL DEFAULT '[]'::jsonb,
  error_message TEXT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (run_id, report_id)
);

CREATE INDEX IF NOT EXISTS idx_report_generation_items_run ON public.report_generation_items(run_id, status);

CREATE TABLE IF NOT EXISTS public.report_submissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID NOT NULL REFERENCES public.report_definitions(id) ON DELETE RESTRICT,
  facility_id UUID NOT NULL REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  due_date DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','submitted','overdue','accepted','rejected')),
  submitted_at TIMESTAMPTZ,
  submitted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  submission_reference TEXT,
  data_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (report_id, facility_id, period_start, period_end)
);

CREATE INDEX IF NOT EXISTS idx_report_submissions_dashboard ON public.report_submissions(facility_id, period_start, status);

-- Categories
INSERT INTO public.report_categories (name, display_order) VALUES
  ('Morbidity & OPD', 10),
  ('HIV/AIDS & Related', 20),
  ('Maternal & Child Health', 30),
  ('Surgical & Clinical', 40),
  ('Disease Surveillance & Programs', 50),
  ('Other Programs & Administration', 60)
ON CONFLICT (name) DO NOTHING;

-- Seed library. These are a configurable seed catalogue, not a claim that every
-- row exactly matches the current DHIMS2 metadata. implementation_status remains
-- 'seeded' until the official CHIM/GHS metadata/data-element mapping is validated.
WITH seeds(code,name,category,description,frequency,params,extractor) AS (
  VALUES
  ('RPT-001','Monthly OPD Morbidity Return','Morbidity & OPD','OPD diagnoses and cases by age group and ICD classification.','monthly','["period","facility","age_group","case_type","icd_code"]','opd_morbidity'),
  ('RPT-002','Monthly OPD Statement','Morbidity & OPD','New, old and repeat outpatient attendance.','monthly','["period","facility","case_type"]','opd_attendance'),
  ('RPT-003','Monthly Malaria Data on Anti-malarial','Morbidity & OPD','Suspected/confirmed malaria and anti-malarial treatment.','monthly','["period","facility","age_group","case_classification"]','malaria'),
  ('RPT-004','Causes of Death Statement','Morbidity & OPD','Mortality by documented cause.','monthly','["period","facility","cause"]','mortality'),
  ('RPT-005','HIV/AIDS Return (HTS)','HIV/AIDS & Related','HIV testing by test and result category.','monthly','["period","facility","test_type","result_category"]','hiv_hts'),
  ('RPT-006','ART Visits (New Adult)','HIV/AIDS & Related','Adult ART initiations.','monthly','["period","facility","age_group"]','art_adult_new'),
  ('RPT-007','ART Visits (Established Adult)','HIV/AIDS & Related','Established adult ART follow-up visits.','monthly','["period","facility","age_group"]','art_adult_followup'),
  ('RPT-008','ART Visits (Pediatrics)','HIV/AIDS & Related','Paediatric ART initiations and follow-up.','monthly','["period","facility","age_group"]','art_paediatric'),
  ('RPT-009','PMTCT Monthly Return Form','HIV/AIDS & Related','PMTCT activity and outcomes.','monthly','["period","facility","pregnancy_status"]','pmtct'),
  ('RPT-010','STI Return','HIV/AIDS & Related','STI cases treated by age group.','monthly','["period","facility","age_group"]','sti'),
  ('RPT-011','VMMC (Male Circumcision)','HIV/AIDS & Related','Male circumcision visits and service totals.','monthly','["period","facility","visit_number"]','vmmc'),
  ('RPT-012','Midwife''s Form A (Monthly Returns)','Maternal & Child Health','Maternal and child health operational return.','monthly','["period","facility","service_type","age_group"]','mch_midwife_a'),
  ('RPT-013','Form B — Family Planning Returns','Maternal & Child Health','Family planning clients and methods.','monthly','["period","facility","method_type","client_type"]','family_planning'),
  ('RPT-014','Form C','Maternal & Child Health','Additional maternal and child health indicators.','monthly','["period","facility"]','mch_form_c'),
  ('RPT-015','Antenatal Total','Maternal & Child Health','Antenatal visits.','monthly','["period","facility","visit_type"]','antenatal'),
  ('RPT-016','Delivery Report','Maternal & Child Health','Deliveries by mode.','monthly','["period","facility","delivery_mode"]','delivery'),
  ('RPT-017','Postnatal Care (PNC)','Maternal & Child Health','PNC visits and outcomes.','monthly','["period","facility","visit_type"]','pnc'),
  ('RPT-018','Comprehensive Abortion Care (CAC)','Maternal & Child Health','CAC services and procedures.','monthly','["period","facility","procedure_type"]','cac'),
  ('RPT-019','EPI (Immunization) Report','Maternal & Child Health','Routine immunization by antigen and age group.','monthly','["period","facility","antigen","age_group"]','epi'),
  ('RPT-020','Monthly Nutrition Report','Maternal & Child Health','Growth monitoring, malnutrition and supplementation.','monthly','["period","facility","age_group"]','nutrition'),
  ('RPT-021','Births & Birthweight','Maternal & Child Health','Birth registration and birthweight indicators.','monthly','["period","facility"]','births'),
  ('RPT-022','Hb Screening','Maternal & Child Health','Haemoglobin screening indicators.','monthly','["period","facility"]','hb_screening'),
  ('RPT-023','Surgeries Report','Surgical & Clinical','Major and minor surgery totals.','monthly','["period","facility","surgery_type"]','surgeries'),
  ('RPT-024','Inpatient Days (IP Days)','Surgical & Clinical','Inpatient days by ward type.','monthly','["period","facility","ward_type"]','inpatient_days'),
  ('RPT-025','IP Admission / Discharge','Surgical & Clinical','Admissions and discharges.','monthly','["period","facility","admission_type"]','ip_admission_discharge'),
  ('RPT-026','IP Morbidity','Surgical & Clinical','Inpatient morbidity by diagnosis.','monthly','["period","facility","diagnosis"]','ip_morbidity'),
  ('RPT-027','Gynaecology & Obstetrics Report','Surgical & Clinical','Gynaecology/obstetric admissions and outcomes.','monthly','["period","facility","condition_type"]','gynae_obstetrics'),
  ('RPT-028','Accidents & Emergency','Surgical & Clinical','Emergency injuries and road traffic accidents.','monthly','["period","facility","injury_type"]','emergency'),
  ('RPT-029','Dental Report','Surgical & Clinical','Dental conditions and attendance.','monthly','["period","facility","condition_type"]','dental'),
  ('RPT-030','Mental Health Report','Surgical & Clinical','Mental health conditions and attendance.','monthly','["period","facility","condition_type"]','mental_health'),
  ('RPT-031','Active MTMSG','Surgical & Clinical','Active case finding for TB and other diseases.','monthly','["period","facility"]','active_case_finding'),
  ('RPT-032','IDSR Weekly Reports','Disease Surveillance & Programs','Weekly notifiable disease surveillance.','weekly','["period","facility","disease"]','idsr_weekly'),
  ('RPT-033','IDSR Monthly Reports','Disease Surveillance & Programs','Monthly notifiable disease surveillance.','monthly','["period","facility","disease"]','idsr_monthly'),
  ('RPT-034','TB Case Findings (New)','Disease Surveillance & Programs','New TB cases by category.','monthly','["period","facility","case_category"]','tb_new'),
  ('RPT-035','Malnutrition (Under 5)','Disease Surveillance & Programs','New under-five malnutrition cases.','monthly','["period","facility","age_group"]','malnutrition_u5'),
  ('RPT-036','Schistosomiasis & FGS','Disease Surveillance & Programs','Schistosomiasis and FGS cases.','monthly','["period","facility","case_type"]','schistosomiasis'),
  ('RPT-037','Buruli Ulcer','Disease Surveillance & Programs','Buruli ulcer burden and treatment completion.','monthly','["period","facility"]','buruli_ulcer'),
  ('RPT-038','SBCC Report','Other Programs & Administration','Social and behaviour change communication indicators.','monthly','["period","facility","indicator"]','sbcc'),
  ('RPT-039','Community Health (CHIS)','Other Programs & Administration','Community health programme indicators.','monthly','["period","facility","program_area"]','chis'),
  ('RPT-040','Administrative Reporting','Other Programs & Administration','Service delivery capacity and administrative indicators.','monthly','["period","facility"]','administrative'),
  ('RPT-041','Laboratory Reports','Other Programs & Administration','Laboratory activity by test category.','monthly','["period","facility","test_type"]','laboratory')
)
INSERT INTO public.report_definitions
  (report_code, report_name, category_id, description, frequency, parameters, extractor_key)
SELECT s.code, s.name, c.id, s.description, s.frequency, s.params::jsonb, s.extractor
FROM seeds s JOIN public.report_categories c ON c.name = s.category
ON CONFLICT (report_code) DO UPDATE SET
  report_name = EXCLUDED.report_name,
  category_id = EXCLUDED.category_id,
  description = EXCLUDED.description,
  frequency = EXCLUDED.frequency,
  parameters = EXCLUDED.parameters,
  extractor_key = EXCLUDED.extractor_key,
  updated_at = now();

ALTER TABLE public.healthcare_facilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.facility_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.facility_report_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_generation_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_generation_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_submissions ENABLE ROW LEVEL SECURITY;

-- Authorization helper: facility membership is the row-level boundary.
CREATE OR REPLACE FUNCTION public.has_facility_access(_user_id UUID, _facility_id UUID)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.facility_memberships fm
    WHERE fm.user_id = _user_id AND fm.facility_id = _facility_id AND fm.is_active = TRUE
  ) OR public.has_role(_user_id, 'admin')
$$;

DROP POLICY IF EXISTS report_categories_read_authenticated ON public.report_categories;
CREATE POLICY report_categories_read_authenticated ON public.report_categories FOR SELECT TO authenticated USING (TRUE);
DROP POLICY IF EXISTS report_definitions_read_authenticated ON public.report_definitions;
CREATE POLICY report_definitions_read_authenticated ON public.report_definitions FOR SELECT TO authenticated USING (is_active = TRUE OR public.has_role((select auth.uid()), 'admin'));

DROP POLICY IF EXISTS healthcare_facilities_access ON public.healthcare_facilities;
CREATE POLICY healthcare_facilities_access ON public.healthcare_facilities FOR SELECT TO authenticated
USING (public.has_facility_access((select auth.uid()), id));
CREATE POLICY healthcare_facilities_admin_write ON public.healthcare_facilities FOR ALL TO authenticated
USING (public.has_role((select auth.uid()), 'admin')) WITH CHECK (public.has_role((select auth.uid()), 'admin'));

DROP POLICY IF EXISTS facility_memberships_self_or_admin ON public.facility_memberships;
CREATE POLICY facility_memberships_self_or_admin ON public.facility_memberships FOR SELECT TO authenticated
USING (user_id = (select auth.uid()) OR public.has_role((select auth.uid()), 'admin'));
CREATE POLICY facility_memberships_admin_write ON public.facility_memberships FOR ALL TO authenticated
USING (public.has_role((select auth.uid()), 'admin')) WITH CHECK (public.has_role((select auth.uid()), 'admin'));

DROP POLICY IF EXISTS facility_report_config_access ON public.facility_report_config;
CREATE POLICY facility_report_config_access ON public.facility_report_config FOR SELECT TO authenticated
USING (public.has_facility_access((select auth.uid()), facility_id));
CREATE POLICY facility_report_config_admin_write ON public.facility_report_config FOR ALL TO authenticated
USING (public.has_role((select auth.uid()), 'admin')) WITH CHECK (public.has_role((select auth.uid()), 'admin'));

DROP POLICY IF EXISTS report_generation_runs_access ON public.report_generation_runs;
CREATE POLICY report_generation_runs_access ON public.report_generation_runs FOR SELECT TO authenticated
USING (public.has_facility_access((select auth.uid()), facility_id));
CREATE POLICY report_generation_runs_insert ON public.report_generation_runs FOR INSERT TO authenticated
WITH CHECK (public.has_facility_access((select auth.uid()), facility_id) AND created_by = (select auth.uid()));
CREATE POLICY report_generation_runs_update ON public.report_generation_runs FOR UPDATE TO authenticated
USING (public.has_facility_access((select auth.uid()), facility_id)) WITH CHECK (public.has_facility_access((select auth.uid()), facility_id));

DROP POLICY IF EXISTS report_generation_items_access ON public.report_generation_items;
CREATE POLICY report_generation_items_access ON public.report_generation_items FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.report_generation_runs r WHERE r.id = run_id AND public.has_facility_access((select auth.uid()), r.facility_id)));
CREATE POLICY report_generation_items_update ON public.report_generation_items FOR UPDATE TO authenticated
USING (EXISTS (SELECT 1 FROM public.report_generation_runs r WHERE r.id = run_id AND public.has_facility_access((select auth.uid()), r.facility_id)))
WITH CHECK (EXISTS (SELECT 1 FROM public.report_generation_runs r WHERE r.id = run_id AND public.has_facility_access((select auth.uid()), r.facility_id)));

DROP POLICY IF EXISTS report_submissions_access ON public.report_submissions;
CREATE POLICY report_submissions_access ON public.report_submissions FOR SELECT TO authenticated
USING (public.has_facility_access((select auth.uid()), facility_id));
CREATE POLICY report_submissions_write ON public.report_submissions FOR ALL TO authenticated
USING (public.has_facility_access((select auth.uid()), facility_id)) WITH CHECK (public.has_facility_access((select auth.uid()), facility_id));

-- Seed sensible default report activation by facility type without hard-coding it in UI.
-- Admins can adjust every facility through facility_report_config.
CREATE OR REPLACE FUNCTION public.seed_facility_reports(_facility_id UUID)
RETURNS INTEGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_type TEXT; v_count INTEGER := 0;
BEGIN
  SELECT facility_type INTO v_type FROM public.healthcare_facilities WHERE id = _facility_id;
  IF v_type IS NULL THEN RAISE EXCEPTION 'Facility not found'; END IF;
  INSERT INTO public.facility_report_config(facility_id, report_id, is_enabled)
  SELECT _facility_id, rd.id, TRUE
  FROM public.report_definitions rd
  WHERE rd.is_active AND (
    (v_type = 'chps_compound' AND rd.report_code IN ('RPT-001','RPT-003','RPT-012','RPT-019','RPT-020','RPT-032')) OR
    (v_type = 'health_centre' AND rd.report_code BETWEEN 'RPT-001' AND 'RPT-041' AND rd.report_code NOT IN ('RPT-005','RPT-006','RPT-007','RPT-008','RPT-009','RPT-011')) OR
    (v_type IN ('district_hospital','regional_hospital','teaching_hospital','specialist_clinic') AND rd.is_active) OR
    (v_type = 'hiv_clinic' AND rd.report_code IN ('RPT-005','RPT-006','RPT-007','RPT-008','RPT-009','RPT-010','RPT-011','RPT-032','RPT-033')) OR
    (v_type = 'maternity_home' AND rd.report_code IN ('RPT-012','RPT-013','RPT-015','RPT-016','RPT-017','RPT-021','RPT-022'))
  )
  ON CONFLICT (facility_id, report_id) DO UPDATE SET is_enabled = TRUE, updated_at = now();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.seed_facility_reports(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seed_facility_reports(UUID) TO authenticated;
