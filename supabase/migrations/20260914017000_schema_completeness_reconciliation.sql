-- Additive schema completeness reconciliation across clinical, operational, billing,
-- laboratory, pharmacy, nutrition, AI, and administrative modules.
-- Existing data is preserved; no existing columns are dropped or renamed.

ALTER TABLE public.admissions
  ADD COLUMN IF NOT EXISTS encounter_id UUID REFERENCES public.encounters(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reason TEXT,
  ADD COLUMN IF NOT EXISTS admitted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS discharge_summary TEXT;
UPDATE public.admissions SET admitted_by = COALESCE(admitted_by, created_by) WHERE admitted_by IS NULL AND created_by IS NOT NULL;
UPDATE public.admissions SET reason = COALESCE(reason, diagnosis) WHERE reason IS NULL AND diagnosis IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_admissions_encounter_id ON public.admissions(encounter_id);

ALTER TABLE public.dental_records
  ADD COLUMN IF NOT EXISTS encounter_id UUID REFERENCES public.encounters(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS tooth_chart JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
CREATE INDEX IF NOT EXISTS idx_dental_records_encounter_id ON public.dental_records(encounter_id);

ALTER TABLE public.diagnoses
  ADD COLUMN IF NOT EXISTS ai_suggested BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_provisional BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS notes TEXT;

ALTER TABLE public.lab_orders ADD COLUMN IF NOT EXISTS lab_test_catalogue_id UUID;
CREATE INDEX IF NOT EXISTS idx_lab_orders_catalogue ON public.lab_orders(lab_test_catalogue_id);
ALTER TABLE public.lab_results
  ADD COLUMN IF NOT EXISTS numeric_value NUMERIC,
  ADD COLUMN IF NOT EXISTS unit TEXT,
  ADD COLUMN IF NOT EXISTS reference_low NUMERIC,
  ADD COLUMN IF NOT EXISTS reference_high NUMERIC,
  ADD COLUMN IF NOT EXISTS abnormal_flag TEXT;

ALTER TABLE public.outside_lab_documents
  ADD COLUMN IF NOT EXISTS ai_analysis TEXT,
  ADD COLUMN IF NOT EXISTS ai_analyzed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS notes TEXT;

ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS membership_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS membership_type TEXT NOT NULL DEFAULT 'standard',
  ADD COLUMN IF NOT EXISTS registration_reason TEXT;

ALTER TABLE public.procedure_notes
  ADD COLUMN IF NOT EXISTS encounter_id UUID REFERENCES public.encounters(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS procedure_code TEXT,
  ADD COLUMN IF NOT EXISTS assistants TEXT,
  ADD COLUMN IF NOT EXISTS performed_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_procedure_notes_encounter_id ON public.procedure_notes(encounter_id);

ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
ALTER TABLE public.video_sessions
  ADD COLUMN IF NOT EXISTS service_order_id UUID REFERENCES public.service_orders(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_video_sessions_service_order_id ON public.video_sessions(service_order_id);

CREATE TABLE IF NOT EXISTS public.icd_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), code TEXT NOT NULL UNIQUE,
  version TEXT NOT NULL DEFAULT 'ICD-10', description TEXT NOT NULL, category TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.icd_codes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS icd_read_all ON public.icd_codes;
CREATE POLICY icd_read_all ON public.icd_codes FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS icd_admin_write ON public.icd_codes;
CREATE POLICY icd_admin_write ON public.icd_codes FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='fk_diagnoses_icd_completeness') THEN
    ALTER TABLE public.diagnoses ADD CONSTRAINT fk_diagnoses_icd_completeness FOREIGN KEY (icd_code) REFERENCES public.icd_codes(code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.stg_guidelines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), condition TEXT NOT NULL, icd_code TEXT,
  summary TEXT, recommended_action TEXT, medications JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.stg_guidelines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stg_read_all ON public.stg_guidelines;
CREATE POLICY stg_read_all ON public.stg_guidelines FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS stg_admin_write ON public.stg_guidelines;
CREATE POLICY stg_admin_write ON public.stg_guidelines FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

CREATE TABLE IF NOT EXISTS public.treatment_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name TEXT NOT NULL, diagnosis TEXT, icd_code TEXT,
  description TEXT, prescriptions JSONB DEFAULT '[]'::jsonb, lab_orders JSONB DEFAULT '[]'::jsonb,
  notes TEXT, created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL, is_ai_generated BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.treatment_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tt_clinical_read ON public.treatment_templates;
CREATE POLICY tt_clinical_read ON public.treatment_templates FOR SELECT TO authenticated USING (public.is_clinical_staff(auth.uid()));
DROP POLICY IF EXISTS tt_clinical_write ON public.treatment_templates;
CREATE POLICY tt_clinical_write ON public.treatment_templates FOR ALL TO authenticated USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

CREATE TABLE IF NOT EXISTS public.lab_test_catalogue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), test_code TEXT NOT NULL UNIQUE, test_name TEXT NOT NULL,
  category TEXT, specimen_type TEXT, unit TEXT, reference_low NUMERIC, reference_high NUMERIC, reference_text TEXT,
  default_charge NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (default_charge >= 0),
  turnaround_minutes INTEGER CHECK (turnaround_minutes IS NULL OR turnaround_minutes > 0),
  active BOOLEAN NOT NULL DEFAULT true, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.lab_orders DROP CONSTRAINT IF EXISTS lab_orders_lab_test_catalogue_id_fkey;
ALTER TABLE public.lab_orders ADD CONSTRAINT lab_orders_lab_test_catalogue_id_fkey FOREIGN KEY (lab_test_catalogue_id) REFERENCES public.lab_test_catalogue(id) ON DELETE SET NULL;
ALTER TABLE public.lab_test_catalogue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS authenticated_read_active_lab_catalogue ON public.lab_test_catalogue;
CREATE POLICY authenticated_read_active_lab_catalogue ON public.lab_test_catalogue FOR SELECT TO authenticated USING (active = true OR public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS admins_manage_lab_catalogue ON public.lab_test_catalogue;
CREATE POLICY admins_manage_lab_catalogue ON public.lab_test_catalogue FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));
CREATE INDEX IF NOT EXISTS idx_lab_catalogue_active_name ON public.lab_test_catalogue(active, test_name);

CREATE TABLE IF NOT EXISTS public.lab_test_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), code TEXT UNIQUE, name TEXT NOT NULL, category TEXT, specimen TEXT,
  method TEXT, price NUMERIC(10,2) NOT NULL DEFAULT 0, turnaround_hours INTEGER, notes TEXT, active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.lab_test_catalog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS staff_read_lab_catalog ON public.lab_test_catalog;
CREATE POLICY staff_read_lab_catalog ON public.lab_test_catalog FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS lab_and_admin_manage_catalog ON public.lab_test_catalog;
CREATE POLICY lab_and_admin_manage_catalog ON public.lab_test_catalog FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'lab_technician')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'lab_technician'));

CREATE TABLE IF NOT EXISTS public.lab_test_parameters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), test_id UUID NOT NULL REFERENCES public.lab_test_catalog(id) ON DELETE CASCADE,
  name TEXT NOT NULL, unit TEXT, ref_low NUMERIC, ref_high NUMERIC, ref_text TEXT, interpretation TEXT,
  display_order INTEGER NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.lab_test_parameters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS staff_read_lab_params ON public.lab_test_parameters;
CREATE POLICY staff_read_lab_params ON public.lab_test_parameters FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS lab_and_admin_manage_params ON public.lab_test_parameters;
CREATE POLICY lab_and_admin_manage_params ON public.lab_test_parameters FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'lab_technician')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'lab_technician'));
CREATE INDEX IF NOT EXISTS idx_ltp_test ON public.lab_test_parameters(test_id);

CREATE TABLE IF NOT EXISTS public.lab_tests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), test_name TEXT, loinc_code TEXT, specimen TEXT, normal_range TEXT, created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.lab_tests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS staff_read_lab_tests ON public.lab_tests;
CREATE POLICY staff_read_lab_tests ON public.lab_tests FOR SELECT TO authenticated USING (public.is_clinical_staff(auth.uid()));
DROP POLICY IF EXISTS admins_write_lab_tests ON public.lab_tests;
CREATE POLICY admins_write_lab_tests ON public.lab_tests FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

CREATE TABLE IF NOT EXISTS public.inpatient_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), admission_id UUID NOT NULL REFERENCES public.admissions(id) ON DELETE CASCADE,
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE, reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewer_name TEXT, reviewer_role TEXT, review_type TEXT NOT NULL DEFAULT 'ward_round', findings TEXT, plan TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.inpatient_reviews ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS staff_manage_inpatient_reviews ON public.inpatient_reviews;
CREATE POLICY staff_manage_inpatient_reviews ON public.inpatient_reviews FOR ALL TO authenticated USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));
CREATE INDEX IF NOT EXISTS idx_ipr_admission ON public.inpatient_reviews(admission_id);

CREATE TABLE IF NOT EXISTS public.anesthetic_assessments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id UUID REFERENCES public.encounters(id) ON DELETE SET NULL, asa_class TEXT, airway_assessment TEXT,
  cardiovascular TEXT, respiratory TEXT, allergies TEXT, medications TEXT, fasting_status TEXT, questionnaire JSONB DEFAULT '{}'::jsonb,
  conclusions TEXT, cleared_for_procedure BOOLEAN DEFAULT false, cleared_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'draft', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.anesthetic_assessments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS aa_patient_read ON public.anesthetic_assessments;
CREATE POLICY aa_patient_read ON public.anesthetic_assessments FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.patients p WHERE p.id=patient_id AND p.user_id=auth.uid()));
DROP POLICY IF EXISTS aa_staff_all ON public.anesthetic_assessments;
CREATE POLICY aa_staff_all ON public.anesthetic_assessments FOR ALL TO authenticated USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

CREATE TABLE IF NOT EXISTS public.pharmacy_inventory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), drug_name TEXT NOT NULL, generic_name TEXT, form TEXT, strength TEXT,
  unit_price NUMERIC(10,2) DEFAULT 0, stock_quantity INTEGER NOT NULL DEFAULT 0, reorder_level INTEGER DEFAULT 20,
  expiry_date DATE, supplier TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.pharmacy_inventory ADD COLUMN IF NOT EXISTS brand_name TEXT, ADD COLUMN IF NOT EXISTS pack_size INTEGER, ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.pharmacy_inventory ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS inv_clinical_read ON public.pharmacy_inventory;
CREATE POLICY inv_clinical_read ON public.pharmacy_inventory FOR SELECT TO authenticated USING (public.is_clinical_staff(auth.uid()));
DROP POLICY IF EXISTS inv_pharma_write ON public.pharmacy_inventory;
CREATE POLICY inv_pharma_write ON public.pharmacy_inventory FOR ALL TO authenticated USING (public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'admin'));

CREATE TABLE IF NOT EXISTS public.pharmacy_goods_receipts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), inventory_id UUID REFERENCES public.pharmacy_inventory(id) ON DELETE SET NULL,
  drug_name TEXT NOT NULL, quantity INTEGER NOT NULL, unit_cost NUMERIC(10,2), supplier TEXT, invoice_number TEXT, expiry_date DATE,
  received_by UUID REFERENCES auth.users(id) ON DELETE SET NULL, approved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ, rejection_reason TEXT, status TEXT NOT NULL DEFAULT 'pending', notes TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.pharmacy_goods_receipts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gr_clinical_read ON public.pharmacy_goods_receipts;
CREATE POLICY gr_clinical_read ON public.pharmacy_goods_receipts FOR SELECT TO authenticated USING (public.is_clinical_staff(auth.uid()));
DROP POLICY IF EXISTS gr_pharma_write ON public.pharmacy_goods_receipts;
CREATE POLICY gr_pharma_write ON public.pharmacy_goods_receipts FOR ALL TO authenticated USING (public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'admin'));

CREATE TABLE IF NOT EXISTS public.meal_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  plan_type TEXT NOT NULL, description TEXT, meals_per_day INTEGER DEFAULT 3, restrictions TEXT, ai_recommendations TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL, active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.meal_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mp_patient_read ON public.meal_plans;
CREATE POLICY mp_patient_read ON public.meal_plans FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.patients p WHERE p.id=patient_id AND p.user_id=auth.uid()));
DROP POLICY IF EXISTS mp_staff_all ON public.meal_plans;
CREATE POLICY mp_staff_all ON public.meal_plans FOR ALL TO authenticated USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'canteen')) WITH CHECK (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'canteen'));

CREATE TABLE IF NOT EXISTS public.meal_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  meal_plan_id UUID REFERENCES public.meal_plans(id) ON DELETE SET NULL, meal_type TEXT NOT NULL, scheduled_for TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', delivered_at TIMESTAMPTZ, notes TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.meal_orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mo_patient_read ON public.meal_orders;
CREATE POLICY mo_patient_read ON public.meal_orders FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.patients p WHERE p.id=patient_id AND p.user_id=auth.uid()));
DROP POLICY IF EXISTS mo_staff_all ON public.meal_orders;
CREATE POLICY mo_staff_all ON public.meal_orders FOR ALL TO authenticated USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'canteen')) WITH CHECK (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'canteen'));

CREATE TABLE IF NOT EXISTS public.ai_case_memory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), patient_id UUID, encounter_id UUID, diagnosis TEXT, icd_code TEXT, symptoms TEXT,
  prescriptions JSONB DEFAULT '[]'::jsonb, outcome TEXT, outcome_notes TEXT, age_group TEXT, gender TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.ai_case_memory ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS acm_clinical_all ON public.ai_case_memory;
CREATE POLICY acm_clinical_all ON public.ai_case_memory FOR ALL TO authenticated USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

CREATE TABLE IF NOT EXISTS public.ai_protocols (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), diagnosis TEXT NOT NULL, icd_code TEXT, protocol_text TEXT NOT NULL,
  case_count INTEGER DEFAULT 0, status TEXT NOT NULL DEFAULT 'pending_review', approved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.ai_protocols ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ap_clinical_read ON public.ai_protocols;
CREATE POLICY ap_clinical_read ON public.ai_protocols FOR SELECT TO authenticated USING (public.is_clinical_staff(auth.uid()));
DROP POLICY IF EXISTS ap_admin_write ON public.ai_protocols;
CREATE POLICY ap_admin_write ON public.ai_protocols FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner'));

CREATE TABLE IF NOT EXISTS public.ai_diagnosis_suggestions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), encounter_id UUID REFERENCES public.encounters(id) ON DELETE CASCADE,
  suggested_icd TEXT REFERENCES public.icd_codes(code) ON DELETE SET NULL, reasoning TEXT, model_version TEXT,
  accepted BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.ai_diagnosis_suggestions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS clinical_staff_manage_ai_diagnosis_suggestions ON public.ai_diagnosis_suggestions;
CREATE POLICY clinical_staff_manage_ai_diagnosis_suggestions ON public.ai_diagnosis_suggestions FOR ALL TO authenticated USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

CREATE TABLE IF NOT EXISTS public.ai_symptom_icd_map (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), symptom TEXT NOT NULL, icd_code TEXT REFERENCES public.icd_codes(code) ON DELETE SET NULL,
  confidence NUMERIC, created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.ai_symptom_icd_map ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS staff_read_symptom_map ON public.ai_symptom_icd_map;
CREATE POLICY staff_read_symptom_map ON public.ai_symptom_icd_map FOR SELECT TO authenticated USING (public.is_clinical_staff(auth.uid()));
DROP POLICY IF EXISTS admins_write_symptom_map ON public.ai_symptom_icd_map;
CREATE POLICY admins_write_symptom_map ON public.ai_symptom_icd_map FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

CREATE TABLE IF NOT EXISTS public.ai_report_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  report_type TEXT NOT NULL DEFAULT 'clinical_summary', requested_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'pending', content TEXT, error TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), completed_at TIMESTAMPTZ
);
ALTER TABLE public.ai_report_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS air_clinical_all ON public.ai_report_requests;
CREATE POLICY air_clinical_all ON public.ai_report_requests FOR ALL TO authenticated USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT, table_name TEXT, record_id UUID, old_data JSONB, new_data JSONB, created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admins_read_audit_logs ON public.audit_logs;
CREATE POLICY admins_read_audit_logs ON public.audit_logs FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin'));

CREATE TABLE IF NOT EXISTS public.sync_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), payload JSONB, synced BOOLEAN DEFAULT false, table_name TEXT
);
ALTER TABLE public.sync_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admins_read_sync_queue ON public.sync_queue;
CREATE POLICY admins_read_sync_queue ON public.sync_queue FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin'));

CREATE TABLE IF NOT EXISTS public.notification_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), channel TEXT NOT NULL DEFAULT 'in_app', payload JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL DEFAULT 5,
  last_error TEXT, next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), delivered_at TIMESTAMPTZ
);
ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS nq_staff_read ON public.notification_queue;
CREATE POLICY nq_staff_read ON public.notification_queue FOR SELECT TO authenticated USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS nq_staff_write ON public.notification_queue;
CREATE POLICY nq_staff_write ON public.notification_queue FOR ALL TO authenticated USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'admin')) WITH CHECK (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'admin'));
CREATE INDEX IF NOT EXISTS notification_queue_due_idx ON public.notification_queue(status, next_attempt_at) WHERE status IN ('pending','processing');

CREATE TABLE IF NOT EXISTS public.bulk_import_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), entity TEXT NOT NULL, filename TEXT, total_rows INTEGER NOT NULL DEFAULT 0,
  inserted_rows INTEGER NOT NULL DEFAULT 0, failed_rows INTEGER NOT NULL DEFAULT 0, errors JSONB NOT NULL DEFAULT '[]'::jsonb,
  status TEXT NOT NULL DEFAULT 'completed', created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.bulk_import_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bij_admin_all ON public.bulk_import_jobs;
CREATE POLICY bij_admin_all ON public.bulk_import_jobs FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

CREATE TABLE IF NOT EXISTS public.vital_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  vital_signs_id UUID, alert_type TEXT NOT NULL, severity TEXT NOT NULL DEFAULT 'critical', details TEXT,
  acknowledged_by UUID REFERENCES auth.users(id) ON DELETE SET NULL, acknowledged_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.vital_alerts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS va_clinical_all ON public.vital_alerts;
CREATE POLICY va_clinical_all ON public.vital_alerts FOR ALL TO authenticated USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

CREATE TABLE IF NOT EXISTS public.billing_overrides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  department TEXT NOT NULL, related_entity_id UUID, reason TEXT NOT NULL, overridden_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.billing_overrides ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bo_clinical_all ON public.billing_overrides;
CREATE POLICY bo_clinical_all ON public.billing_overrides FOR ALL TO authenticated USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

DO $do$
DECLARE r record;
BEGIN
  FOR r IN SELECT c.relname AS table_name FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND c.relname NOT IN ('system_audit_log','patient_audit') LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS audit_operational_row_change ON public.%I', r.table_name);
    EXECUTE format('CREATE TRIGGER audit_operational_row_change AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.audit_operational_row_change()', r.table_name);
  END LOOP;
END $do$;
NOTIFY pgrst, 'reload schema';