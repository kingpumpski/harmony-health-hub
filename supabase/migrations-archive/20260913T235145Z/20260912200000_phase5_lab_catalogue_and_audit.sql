-- Phase 5: structured laboratory catalogue, result metadata, and patient audit trail.

CREATE TABLE IF NOT EXISTS public.lab_test_catalogue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  test_code TEXT NOT NULL UNIQUE,
  test_name TEXT NOT NULL,
  category TEXT,
  specimen_type TEXT,
  unit TEXT,
  reference_low NUMERIC,
  reference_high NUMERIC,
  reference_text TEXT,
  default_charge NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (default_charge >= 0),
  turnaround_minutes INTEGER CHECK (turnaround_minutes IS NULL OR turnaround_minutes > 0),
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_lab_catalogue_active_name ON public.lab_test_catalogue(active, test_name);

ALTER TABLE public.lab_orders ADD COLUMN IF NOT EXISTS lab_test_catalogue_id UUID REFERENCES public.lab_test_catalogue(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_lab_orders_catalogue ON public.lab_orders(lab_test_catalogue_id);

ALTER TABLE public.lab_results
  ADD COLUMN IF NOT EXISTS numeric_value NUMERIC,
  ADD COLUMN IF NOT EXISTS unit TEXT,
  ADD COLUMN IF NOT EXISTS reference_low NUMERIC,
  ADD COLUMN IF NOT EXISTS reference_high NUMERIC,
  ADD COLUMN IF NOT EXISTS abnormal_flag TEXT;

ALTER TABLE public.lab_test_catalogue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "authenticated read active lab catalogue" ON public.lab_test_catalogue;
CREATE POLICY "authenticated read active lab catalogue" ON public.lab_test_catalogue FOR SELECT TO authenticated USING (active = true OR public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS "admins manage lab catalogue" ON public.lab_test_catalogue;
CREATE POLICY "admins manage lab catalogue" ON public.lab_test_catalogue FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));
DROP TRIGGER IF EXISTS t_lab_catalogue_updated ON public.lab_test_catalogue;
CREATE TRIGGER t_lab_catalogue_updated BEFORE UPDATE ON public.lab_test_catalogue FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TABLE IF NOT EXISTS public.patient_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  changed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  old_record JSONB,
  new_record JSONB,
  changed_fields TEXT[] NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS idx_patient_audit_patient_time ON public.patient_audit_log(patient_id, changed_at DESC);
ALTER TABLE public.patient_audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff read patient audit" ON public.patient_audit_log;
CREATE POLICY "staff read patient audit" ON public.patient_audit_log FOR SELECT TO authenticated USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS "admins manage patient audit" ON public.patient_audit_log;
CREATE POLICY "admins manage patient audit" ON public.patient_audit_log FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

CREATE OR REPLACE FUNCTION public.audit_patient_changes()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE old_json JSONB; new_json JSONB; changed TEXT[] := '{}'; key TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.patient_audit_log(patient_id, changed_by, action, new_record) VALUES (NEW.id, auth.uid(), TG_OP, to_jsonb(NEW)); RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.patient_audit_log(patient_id, changed_by, action, old_record) VALUES (OLD.id, auth.uid(), TG_OP, to_jsonb(OLD)); RETURN OLD;
  END IF;
  old_json := to_jsonb(OLD); new_json := to_jsonb(NEW);
  FOR key IN SELECT jsonb_object_keys(new_json) LOOP
    IF old_json -> key IS DISTINCT FROM new_json -> key THEN changed := array_append(changed, key); END IF;
  END LOOP;
  IF cardinality(changed) > 0 THEN
    INSERT INTO public.patient_audit_log(patient_id, changed_by, action, old_record, new_record, changed_fields) VALUES (NEW.id, auth.uid(), TG_OP, old_json, new_json, changed);
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS t_patient_audit_changes ON public.patients;
CREATE TRIGGER t_patient_audit_changes AFTER INSERT OR UPDATE OR DELETE ON public.patients FOR EACH ROW EXECUTE FUNCTION public.audit_patient_changes();

INSERT INTO public.lab_test_catalogue (test_code, test_name, category, specimen_type, unit, reference_text, default_charge) VALUES
('FBC', 'Full Blood Count', 'Hematology', 'EDTA blood', NULL, 'Use laboratory validated adult/pediatric ranges', 0),
('FBS', 'Fasting Blood Sugar', 'Chemistry', 'Fluoride plasma', 'mmol/L', '3.9–5.5 mmol/L', 0),
('RBS', 'Random Blood Sugar', 'Chemistry', 'Fluoride plasma', 'mmol/L', 'Laboratory validated range', 0),
('LFT', 'Liver Function Test', 'Chemistry', 'Serum', NULL, 'Panel; see individual analytes', 0),
('U&E', 'Urea & Electrolytes', 'Chemistry', 'Serum', NULL, 'Panel; see individual analytes', 0),
('URINALYSIS', 'Urinalysis', 'Clinical Chemistry', 'Urine', NULL, 'Laboratory validated range', 0)
ON CONFLICT (test_code) DO NOTHING;
