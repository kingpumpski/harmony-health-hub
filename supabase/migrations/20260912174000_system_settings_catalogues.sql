-- The catalogue's canonical creation migration is timestamped later in this
-- historical chain. Create its full compatible shape before this migration's RLS
-- statements reference it; the later CREATE TABLE IF NOT EXISTS remains idempotent.
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

CREATE TABLE IF NOT EXISTS public.facility_departments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  department_code TEXT NOT NULL UNIQUE,
  department_name TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO public.facility_departments(department_code,department_name) VALUES
 ('consultation','Consultation'),('laboratory','Laboratory'),('imaging','Imaging / Radiology'),('pharmacy','Pharmacy'),('nursing','Nursing'),('maternity','Maternity'),('theatre','Theatre'),('emergency','Emergency'),('accounts','Accounts / Billing'),('front_desk','Front Desk'),('canteen','Canteen / Nutrition'),('administration','Administration')
ON CONFLICT DO NOTHING;
ALTER TABLE public.facility_departments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "department catalogue read" ON public.facility_departments;
CREATE POLICY "department catalogue read" ON public.facility_departments FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "department catalogue admin write" ON public.facility_departments;
CREATE POLICY "department catalogue admin write" ON public.facility_departments FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin'::public.app_role)) WITH CHECK (public.has_role(auth.uid(),'admin'::public.app_role));

ALTER TABLE public.service_tariffs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service tariffs staff read" ON public.service_tariffs;
CREATE POLICY "service tariffs staff read" ON public.service_tariffs FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "service tariffs admin write" ON public.service_tariffs;
CREATE POLICY "service tariffs admin write" ON public.service_tariffs FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin'::public.app_role)) WITH CHECK (public.has_role(auth.uid(),'admin'::public.app_role));

ALTER TABLE public.lab_test_catalogue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "lab catalogue staff read" ON public.lab_test_catalogue;
CREATE POLICY "lab catalogue staff read" ON public.lab_test_catalogue FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "lab catalogue admin write" ON public.lab_test_catalogue;
CREATE POLICY "lab catalogue admin write" ON public.lab_test_catalogue FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'lab_technician'::public.app_role)) WITH CHECK (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'lab_technician'::public.app_role));
