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
CREATE POLICY "department catalogue admin write" ON public.facility_departments FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

ALTER TABLE public.service_tariffs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service tariffs staff read" ON public.service_tariffs;
CREATE POLICY "service tariffs staff read" ON public.service_tariffs FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "service tariffs admin write" ON public.service_tariffs;
CREATE POLICY "service tariffs admin write" ON public.service_tariffs FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

-- Laboratory catalogue policies are installed by the later phase-5 catalogue migration.
-- Keep this early catalogue migration independent of tables that do not exist yet.
