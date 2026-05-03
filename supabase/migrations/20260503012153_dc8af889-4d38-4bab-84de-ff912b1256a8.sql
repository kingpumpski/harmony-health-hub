
-- ICD library
CREATE TABLE public.icd_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  version TEXT NOT NULL DEFAULT 'ICD-10',
  description TEXT NOT NULL,
  category TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.icd_codes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "icd_read_all" ON public.icd_codes FOR SELECT TO authenticated USING (true);
CREATE POLICY "icd_admin_write" ON public.icd_codes FOR ALL TO authenticated USING (has_role(auth.uid(),'admin')) WITH CHECK (has_role(auth.uid(),'admin'));

-- STG Ghana
CREATE TABLE public.stg_guidelines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  condition TEXT NOT NULL,
  icd_code TEXT,
  summary TEXT,
  recommended_action TEXT,
  medications JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.stg_guidelines ENABLE ROW LEVEL SECURITY;
CREATE POLICY "stg_read_all" ON public.stg_guidelines FOR SELECT TO authenticated USING (true);
CREATE POLICY "stg_admin_write" ON public.stg_guidelines FOR ALL TO authenticated USING (has_role(auth.uid(),'admin')) WITH CHECK (has_role(auth.uid(),'admin'));

-- Treatment templates
CREATE TABLE public.treatment_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  diagnosis TEXT,
  icd_code TEXT,
  description TEXT,
  prescriptions JSONB DEFAULT '[]'::jsonb,
  lab_orders JSONB DEFAULT '[]'::jsonb,
  notes TEXT,
  created_by UUID,
  is_ai_generated BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.treatment_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tt_clinical_read" ON public.treatment_templates FOR SELECT TO authenticated USING (is_clinical_staff(auth.uid()));
CREATE POLICY "tt_clinical_write" ON public.treatment_templates FOR ALL TO authenticated USING (is_clinical_staff(auth.uid())) WITH CHECK (is_clinical_staff(auth.uid()));
CREATE TRIGGER tt_touch BEFORE UPDATE ON public.treatment_templates FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Add provisional flag to existing diagnoses
ALTER TABLE public.diagnoses ADD COLUMN IF NOT EXISTS is_provisional BOOLEAN DEFAULT false;
ALTER TABLE public.diagnoses ADD COLUMN IF NOT EXISTS notes TEXT;

-- Procedure notes
CREATE TABLE public.procedure_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  encounter_id UUID,
  procedure_name TEXT NOT NULL,
  procedure_code TEXT,
  template_used TEXT,
  indication TEXT,
  findings TEXT,
  technique TEXT,
  complications TEXT,
  post_op_plan TEXT,
  performed_by UUID,
  assistants TEXT,
  performed_at TIMESTAMPTZ DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'draft',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.procedure_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pn_patient_read" ON public.procedure_notes FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM patients p WHERE p.id=patient_id AND p.user_id=auth.uid()));
CREATE POLICY "pn_staff_all" ON public.procedure_notes FOR ALL TO authenticated USING (is_clinical_staff(auth.uid())) WITH CHECK (is_clinical_staff(auth.uid()));
CREATE TRIGGER pn_touch BEFORE UPDATE ON public.procedure_notes FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Anesthetic assessments
CREATE TABLE public.anesthetic_assessments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  encounter_id UUID,
  asa_class TEXT,
  airway_assessment TEXT,
  cardiovascular TEXT,
  respiratory TEXT,
  allergies TEXT,
  medications TEXT,
  fasting_status TEXT,
  questionnaire JSONB DEFAULT '{}'::jsonb,
  conclusions TEXT,
  cleared_for_procedure BOOLEAN DEFAULT false,
  cleared_by UUID,
  status TEXT NOT NULL DEFAULT 'draft',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.anesthetic_assessments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aa_patient_read" ON public.anesthetic_assessments FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM patients p WHERE p.id=patient_id AND p.user_id=auth.uid()));
CREATE POLICY "aa_staff_all" ON public.anesthetic_assessments FOR ALL TO authenticated USING (is_clinical_staff(auth.uid())) WITH CHECK (is_clinical_staff(auth.uid()));
CREATE TRIGGER aa_touch BEFORE UPDATE ON public.anesthetic_assessments FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Outside lab documents
CREATE TABLE public.outside_lab_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  document_type TEXT NOT NULL,
  title TEXT,
  storage_path TEXT NOT NULL,
  mime_type TEXT,
  uploaded_by UUID,
  ai_analysis TEXT,
  ai_analyzed_at TIMESTAMPTZ,
  reviewed_by UUID,
  reviewed_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.outside_lab_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "old_patient_rw" ON public.outside_lab_documents FOR ALL TO authenticated
  USING (EXISTS(SELECT 1 FROM patients p WHERE p.id=patient_id AND p.user_id=auth.uid()) OR is_clinical_staff(auth.uid()))
  WITH CHECK (EXISTS(SELECT 1 FROM patients p WHERE p.id=patient_id AND p.user_id=auth.uid()) OR is_clinical_staff(auth.uid()));

-- Pharmacy inventory
CREATE TABLE public.pharmacy_inventory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  drug_name TEXT NOT NULL,
  generic_name TEXT,
  form TEXT,
  strength TEXT,
  unit_price NUMERIC(10,2) DEFAULT 0,
  stock_quantity INTEGER NOT NULL DEFAULT 0,
  reorder_level INTEGER DEFAULT 20,
  expiry_date DATE,
  supplier TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.pharmacy_inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "inv_clinical_read" ON public.pharmacy_inventory FOR SELECT TO authenticated USING (is_clinical_staff(auth.uid()));
CREATE POLICY "inv_pharma_write" ON public.pharmacy_inventory FOR ALL TO authenticated USING (has_role(auth.uid(),'pharmacist') OR has_role(auth.uid(),'admin')) WITH CHECK (has_role(auth.uid(),'pharmacist') OR has_role(auth.uid(),'admin'));
CREATE TRIGGER inv_touch BEFORE UPDATE ON public.pharmacy_inventory FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Pharmacy goods receipts
CREATE TABLE public.pharmacy_goods_receipts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inventory_id UUID,
  drug_name TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  unit_cost NUMERIC(10,2),
  supplier TEXT,
  invoice_number TEXT,
  expiry_date DATE,
  received_by UUID,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.pharmacy_goods_receipts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "gr_clinical_read" ON public.pharmacy_goods_receipts FOR SELECT TO authenticated USING (is_clinical_staff(auth.uid()));
CREATE POLICY "gr_pharma_write" ON public.pharmacy_goods_receipts FOR ALL TO authenticated USING (has_role(auth.uid(),'pharmacist') OR has_role(auth.uid(),'admin')) WITH CHECK (has_role(auth.uid(),'pharmacist') OR has_role(auth.uid(),'admin'));

-- Auto-update inventory on receipt
CREATE OR REPLACE FUNCTION public.apply_goods_receipt() RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF NEW.inventory_id IS NOT NULL THEN
    UPDATE public.pharmacy_inventory
      SET stock_quantity = stock_quantity + NEW.quantity,
          updated_at = now()
    WHERE id = NEW.inventory_id;
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER apply_goods_receipt_trg AFTER INSERT ON public.pharmacy_goods_receipts FOR EACH ROW EXECUTE FUNCTION public.apply_goods_receipt();

-- Meal plans
CREATE TABLE public.meal_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  plan_type TEXT NOT NULL,
  description TEXT,
  meals_per_day INTEGER DEFAULT 3,
  restrictions TEXT,
  ai_recommendations TEXT,
  created_by UUID,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.meal_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "mp_patient_read" ON public.meal_plans FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM patients p WHERE p.id=patient_id AND p.user_id=auth.uid()));
CREATE POLICY "mp_staff_all" ON public.meal_plans FOR ALL TO authenticated USING (is_clinical_staff(auth.uid()) OR has_role(auth.uid(),'canteen')) WITH CHECK (is_clinical_staff(auth.uid()) OR has_role(auth.uid(),'canteen'));

-- Meal orders
CREATE TABLE public.meal_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  meal_plan_id UUID,
  meal_type TEXT NOT NULL,
  scheduled_for TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  delivered_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.meal_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "mo_patient_read" ON public.meal_orders FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM patients p WHERE p.id=patient_id AND p.user_id=auth.uid()));
CREATE POLICY "mo_staff_all" ON public.meal_orders FOR ALL TO authenticated USING (is_clinical_staff(auth.uid()) OR has_role(auth.uid(),'canteen')) WITH CHECK (is_clinical_staff(auth.uid()) OR has_role(auth.uid(),'canteen'));

-- Dental
CREATE TABLE public.dental_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  encounter_id UUID,
  tooth_chart JSONB DEFAULT '{}'::jsonb,
  examination TEXT,
  treatment_plan TEXT,
  procedures_performed TEXT,
  performed_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.dental_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "dr_patient_read" ON public.dental_records FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM patients p WHERE p.id=patient_id AND p.user_id=auth.uid()));
CREATE POLICY "dr_staff_all" ON public.dental_records FOR ALL TO authenticated USING (is_clinical_staff(auth.uid())) WITH CHECK (is_clinical_staff(auth.uid()));

-- AI case memory for retrieval-based learning
CREATE TABLE public.ai_case_memory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID,
  encounter_id UUID,
  diagnosis TEXT,
  icd_code TEXT,
  symptoms TEXT,
  prescriptions JSONB DEFAULT '[]'::jsonb,
  outcome TEXT,
  outcome_notes TEXT,
  age_group TEXT,
  gender TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.ai_case_memory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "acm_clinical_all" ON public.ai_case_memory FOR ALL TO authenticated USING (is_clinical_staff(auth.uid())) WITH CHECK (is_clinical_staff(auth.uid()));

-- AI synthesized protocols
CREATE TABLE public.ai_protocols (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  diagnosis TEXT NOT NULL,
  icd_code TEXT,
  protocol_text TEXT NOT NULL,
  case_count INTEGER DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending_review',
  approved_by UUID,
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.ai_protocols ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ap_clinical_read" ON public.ai_protocols FOR SELECT TO authenticated USING (is_clinical_staff(auth.uid()));
CREATE POLICY "ap_admin_write" ON public.ai_protocols FOR ALL TO authenticated USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner')) WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner'));

-- Vital alerts log
CREATE TABLE public.vital_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  vital_signs_id UUID,
  alert_type TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'critical',
  details TEXT,
  acknowledged_by UUID,
  acknowledged_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.vital_alerts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "va_clinical_all" ON public.vital_alerts FOR ALL TO authenticated USING (is_clinical_staff(auth.uid())) WITH CHECK (is_clinical_staff(auth.uid()));

-- Billing override audit
CREATE TABLE public.billing_overrides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  department TEXT NOT NULL,
  related_entity_id UUID,
  reason TEXT NOT NULL,
  overridden_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.billing_overrides ENABLE ROW LEVEL SECURITY;
CREATE POLICY "bo_clinical_all" ON public.billing_overrides FOR ALL TO authenticated USING (is_clinical_staff(auth.uid())) WITH CHECK (is_clinical_staff(auth.uid()));

-- Auto-trigger vital alerts on critical vitals + broadcast notification
CREATE OR REPLACE FUNCTION public.check_critical_vitals() RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public AS $$
DECLARE
  alert_msgs TEXT[] := ARRAY[]::TEXT[];
  alert_severity TEXT := 'warning';
BEGIN
  IF NEW.systolic IS NOT NULL AND (NEW.systolic >= 180 OR NEW.systolic <= 90) THEN
    alert_msgs := array_append(alert_msgs, 'BP systolic ' || NEW.systolic);
    alert_severity := 'critical';
  END IF;
  IF NEW.diastolic IS NOT NULL AND (NEW.diastolic >= 120 OR NEW.diastolic <= 60) THEN
    alert_msgs := array_append(alert_msgs, 'BP diastolic ' || NEW.diastolic);
    alert_severity := 'critical';
  END IF;
  IF NEW.temperature IS NOT NULL AND (NEW.temperature >= 39 OR NEW.temperature <= 35) THEN
    alert_msgs := array_append(alert_msgs, 'Temp ' || NEW.temperature || '°C');
    alert_severity := 'critical';
  END IF;
  IF NEW.oxygen_saturation IS NOT NULL AND NEW.oxygen_saturation <= 92 THEN
    alert_msgs := array_append(alert_msgs, 'SpO2 ' || NEW.oxygen_saturation || '%');
    alert_severity := 'critical';
  END IF;
  IF NEW.pulse_rate IS NOT NULL AND (NEW.pulse_rate >= 130 OR NEW.pulse_rate <= 40) THEN
    alert_msgs := array_append(alert_msgs, 'HR ' || NEW.pulse_rate);
    alert_severity := 'critical';
  END IF;

  IF array_length(alert_msgs,1) IS NOT NULL THEN
    INSERT INTO public.vital_alerts(patient_id, vital_signs_id, alert_type, severity, details)
    VALUES (NEW.patient_id, NEW.id, 'abnormal_vitals', alert_severity, array_to_string(alert_msgs, ' · '));

    -- Broadcast notifications to clinical roles
    INSERT INTO public.notifications(recipient_role, title, message, severity, category, related_patient_id, related_entity_id)
    SELECT r, '🚨 Critical vitals',
           'Patient requires immediate attention: ' || array_to_string(alert_msgs, ' · '),
           'critical', 'triage', NEW.patient_id, NEW.id
    FROM unnest(ARRAY['practitioner','nurse','admin']::app_role[]) AS r;
  END IF;

  RETURN NEW;
END; $$;

CREATE TRIGGER vital_signs_critical_trg AFTER INSERT ON public.vital_signs FOR EACH ROW EXECUTE FUNCTION public.check_critical_vitals();

-- Storage bucket for outside lab docs
INSERT INTO storage.buckets (id, name, public) VALUES ('outside-lab', 'outside-lab', false) ON CONFLICT (id) DO NOTHING;

CREATE POLICY "outside_lab_upload" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'outside-lab');
CREATE POLICY "outside_lab_read" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'outside-lab');
CREATE POLICY "outside_lab_delete" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'outside-lab' AND (is_clinical_staff(auth.uid()) OR auth.uid()::text = (storage.foldername(name))[1]));

-- Seed ICD codes (a starter set - users can expand via admin)
INSERT INTO public.icd_codes (code, version, description, category) VALUES
('A09', 'ICD-10', 'Diarrhoea and gastroenteritis of presumed infectious origin', 'Infectious'),
('B50', 'ICD-10', 'Plasmodium falciparum malaria', 'Infectious'),
('B54', 'ICD-10', 'Unspecified malaria', 'Infectious'),
('E10', 'ICD-10', 'Type 1 diabetes mellitus', 'Endocrine'),
('E11', 'ICD-10', 'Type 2 diabetes mellitus', 'Endocrine'),
('I10', 'ICD-10', 'Essential (primary) hypertension', 'Cardiovascular'),
('I20', 'ICD-10', 'Angina pectoris', 'Cardiovascular'),
('I21', 'ICD-10', 'Acute myocardial infarction', 'Cardiovascular'),
('J06', 'ICD-10', 'Acute upper respiratory infection', 'Respiratory'),
('J18', 'ICD-10', 'Pneumonia, unspecified organism', 'Respiratory'),
('J45', 'ICD-10', 'Asthma', 'Respiratory'),
('K29', 'ICD-10', 'Gastritis and duodenitis', 'Digestive'),
('N39', 'ICD-10', 'Other disorders of urinary system', 'Genitourinary'),
('O80', 'ICD-10', 'Single spontaneous delivery', 'Maternity'),
('R50', 'ICD-10', 'Fever of unknown origin', 'Symptoms'),
('R51', 'ICD-10', 'Headache', 'Symptoms'),
('Z00', 'ICD-10', 'General examination without complaint', 'Other')
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.stg_guidelines (condition, icd_code, summary, recommended_action, medications) VALUES
('Malaria (uncomplicated)', 'B54', 'Confirm with RDT/microscopy. Use Artemisinin Combination Therapy.', 'Artemether-Lumefantrine 6 doses over 3 days', '[{"drug":"Artemether-Lumefantrine","dosage":"4 tabs","frequency":"BD","duration":"3 days"}]'::jsonb),
('Hypertension', 'I10', 'Lifestyle + first-line antihypertensive per Ghana STG.', 'Start Amlodipine 5mg daily; titrate.', '[{"drug":"Amlodipine","dosage":"5mg","frequency":"OD","duration":"30 days"}]'::jsonb),
('Type 2 diabetes', 'E11', 'Lifestyle + metformin first line.', 'Metformin 500mg BD, increase to 1g BD as tolerated.', '[{"drug":"Metformin","dosage":"500mg","frequency":"BD","duration":"30 days"}]'::jsonb),
('Pneumonia (community acquired)', 'J18', 'Antibiotics + supportive care; admit if severe.', 'Amoxicillin 1g TDS x 7 days', '[{"drug":"Amoxicillin","dosage":"1g","frequency":"TDS","duration":"7 days"}]'::jsonb),
('UTI', 'N39', 'Empirical antibiotics; urinalysis & culture if recurrent.', 'Nitrofurantoin 100mg BD x 5 days', '[{"drug":"Nitrofurantoin","dosage":"100mg","frequency":"BD","duration":"5 days"}]'::jsonb)
ON CONFLICT DO NOTHING;

-- Seed pharmacy inventory starters
INSERT INTO public.pharmacy_inventory (drug_name, generic_name, form, strength, unit_price, stock_quantity, reorder_level) VALUES
('Paracetamol', 'Paracetamol', 'Tablet', '500mg', 0.50, 500, 100),
('Amoxicillin', 'Amoxicillin', 'Capsule', '500mg', 1.20, 220, 80),
('Amlodipine', 'Amlodipine', 'Tablet', '5mg', 0.80, 150, 50),
('Metformin', 'Metformin', 'Tablet', '500mg', 0.60, 300, 100),
('Artemether-Lumefantrine', 'AL', 'Tablet', '20/120mg', 5.00, 90, 40)
ON CONFLICT DO NOTHING;

-- Realtime publications
ALTER PUBLICATION supabase_realtime ADD TABLE public.vital_alerts;
ALTER PUBLICATION supabase_realtime ADD TABLE public.outside_lab_documents;
ALTER PUBLICATION supabase_realtime ADD TABLE public.pharmacy_inventory;
ALTER PUBLICATION supabase_realtime ADD TABLE public.meal_orders;
