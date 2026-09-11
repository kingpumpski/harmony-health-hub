
-- FACILITY SETTINGS
CREATE TABLE public.facility_settings (
  id TEXT PRIMARY KEY DEFAULT 'default',
  facility_name TEXT NOT NULL DEFAULT 'MediCare Pro Hospital',
  payment_flow TEXT NOT NULL DEFAULT 'streamlined',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON public.facility_settings TO authenticated;
GRANT ALL ON public.facility_settings TO service_role;
ALTER TABLE public.facility_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone signed in can read settings" ON public.facility_settings FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins manage settings" ON public.facility_settings FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));
CREATE TRIGGER fs_touch BEFORE UPDATE ON public.facility_settings FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
INSERT INTO public.facility_settings (id) VALUES ('default') ON CONFLICT DO NOTHING;

-- SERVICE ORDERS (payment gating)
CREATE TABLE public.service_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id UUID REFERENCES public.encounters(id) ON DELETE SET NULL,
  department TEXT NOT NULL,
  service_name TEXT NOT NULL,
  related_entity_id UUID,
  invoice_id UUID REFERENCES public.invoices(id) ON DELETE SET NULL,
  amount NUMERIC(10,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending_payment',
  notes TEXT,
  requested_by UUID,
  approved_by UUID,
  approved_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_service_orders_status ON public.service_orders(status);
CREATE INDEX idx_service_orders_patient ON public.service_orders(patient_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.service_orders TO authenticated;
GRANT ALL ON public.service_orders TO service_role;
ALTER TABLE public.service_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Staff manage service orders" ON public.service_orders FOR ALL TO authenticated
  USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'specialist_nurse'))
  WITH CHECK (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'specialist_nurse'));
CREATE POLICY "Patients view own service orders" ON public.service_orders FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.patients p WHERE p.id = service_orders.patient_id AND p.user_id = auth.uid()));
CREATE TRIGGER so_touch BEFORE UPDATE ON public.service_orders FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- LAB TEST CATALOGUE
CREATE TABLE public.lab_test_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE,
  name TEXT NOT NULL,
  category TEXT,
  specimen TEXT,
  method TEXT,
  price NUMERIC(10,2) NOT NULL DEFAULT 0,
  turnaround_hours INTEGER,
  notes TEXT,
  active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lab_test_catalog TO authenticated;
GRANT ALL ON public.lab_test_catalog TO service_role;
ALTER TABLE public.lab_test_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Staff read lab catalog" ON public.lab_test_catalog FOR SELECT TO authenticated USING (true);
CREATE POLICY "Lab and admin manage catalog" ON public.lab_test_catalog FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'lab_technician'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'lab_technician'));
CREATE TRIGGER ltc_touch BEFORE UPDATE ON public.lab_test_catalog FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TABLE public.lab_test_parameters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id UUID NOT NULL REFERENCES public.lab_test_catalog(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  unit TEXT,
  ref_low NUMERIC,
  ref_high NUMERIC,
  ref_text TEXT,
  interpretation TEXT,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ltp_test ON public.lab_test_parameters(test_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lab_test_parameters TO authenticated;
GRANT ALL ON public.lab_test_parameters TO service_role;
ALTER TABLE public.lab_test_parameters ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Staff read lab params" ON public.lab_test_parameters FOR SELECT TO authenticated USING (true);
CREATE POLICY "Lab and admin manage params" ON public.lab_test_parameters FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'lab_technician'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'lab_technician'));

-- ADMISSIONS
CREATE TABLE public.admissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id UUID REFERENCES public.encounters(id) ON DELETE SET NULL,
  ward TEXT,
  bed TEXT,
  reason TEXT,
  admitted_by UUID,
  admitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'admitted',
  discharge_summary TEXT,
  discharged_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_admissions_status ON public.admissions(status);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.admissions TO authenticated;
GRANT ALL ON public.admissions TO service_role;
ALTER TABLE public.admissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Staff manage admissions" ON public.admissions FOR ALL TO authenticated
  USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'specialist_nurse'))
  WITH CHECK (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'specialist_nurse'));
CREATE POLICY "Patients view own admissions" ON public.admissions FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.patients p WHERE p.id = admissions.patient_id AND p.user_id = auth.uid()));
CREATE TRIGGER adm_touch BEFORE UPDATE ON public.admissions FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TABLE public.inpatient_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admission_id UUID NOT NULL REFERENCES public.admissions(id) ON DELETE CASCADE,
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  reviewed_by UUID,
  reviewer_name TEXT,
  reviewer_role TEXT,
  review_type TEXT NOT NULL DEFAULT 'ward_round',
  findings TEXT,
  plan TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ipr_admission ON public.inpatient_reviews(admission_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.inpatient_reviews TO authenticated;
GRANT ALL ON public.inpatient_reviews TO service_role;
ALTER TABLE public.inpatient_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Staff manage inpatient reviews" ON public.inpatient_reviews FOR ALL TO authenticated
  USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'specialist_nurse'))
  WITH CHECK (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'specialist_nurse'));
CREATE POLICY "Patients view own reviews" ON public.inpatient_reviews FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.patients p WHERE p.id = inpatient_reviews.patient_id AND p.user_id = auth.uid()));
