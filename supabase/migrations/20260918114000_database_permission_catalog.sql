-- Database-backed permission catalog and role mapping.
-- UI permission filtering is additive; existing RPC/RLS role checks remain authoritative.

CREATE TABLE IF NOT EXISTS public.permissions (
  permission_key TEXT PRIMARY KEY,
  description TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.role_permissions (
  role public.app_role NOT NULL,
  permission_key TEXT NOT NULL REFERENCES public.permissions(permission_key) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (role, permission_key)
);

ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.permissions TO authenticated;
GRANT SELECT ON public.role_permissions TO authenticated;
GRANT ALL ON public.permissions TO service_role;
GRANT ALL ON public.role_permissions TO service_role;

DROP POLICY IF EXISTS permissions_authenticated_read ON public.permissions;
CREATE POLICY permissions_authenticated_read ON public.permissions FOR SELECT TO authenticated USING (is_active OR public.has_role(auth.uid(),'admin'));

DROP POLICY IF EXISTS permissions_admin_insert ON public.permissions;
CREATE POLICY permissions_admin_insert ON public.permissions FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS permissions_admin_update ON public.permissions;
CREATE POLICY permissions_admin_update ON public.permissions FOR UPDATE TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS permissions_admin_delete ON public.permissions;
CREATE POLICY permissions_admin_delete ON public.permissions FOR DELETE TO authenticated USING (public.has_role(auth.uid(),'admin'));

DROP POLICY IF EXISTS role_permissions_read_own ON public.role_permissions;
CREATE POLICY role_permissions_read_own ON public.role_permissions FOR SELECT TO authenticated
USING (role IN (SELECT ur.role FROM public.user_roles ur WHERE ur.user_id=auth.uid()) OR public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS role_permissions_admin_insert ON public.role_permissions;
CREATE POLICY role_permissions_admin_insert ON public.role_permissions FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS role_permissions_admin_update ON public.role_permissions;
CREATE POLICY role_permissions_admin_update ON public.role_permissions FOR UPDATE TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS role_permissions_admin_delete ON public.role_permissions;
CREATE POLICY role_permissions_admin_delete ON public.role_permissions FOR DELETE TO authenticated USING (public.has_role(auth.uid(),'admin'));

INSERT INTO public.permissions(permission_key,description)
VALUES ('dashboard','Harmony Health Hub dashboard navigation capability'),('patients','Harmony Health Hub patients navigation capability'),('registration','Harmony Health Hub registration navigation capability'),('appointments','Harmony Health Hub appointments navigation capability'),('triage','Harmony Health Hub triage navigation capability'),('encounters','Harmony Health Hub encounters navigation capability'),('clinical_operations','Harmony Health Hub clinical operations navigation capability'),('ward','Harmony Health Hub ward navigation capability'),('handover','Harmony Health Hub handover navigation capability'),('emergency','Harmony Health Hub emergency navigation capability'),('theatre','Harmony Health Hub theatre navigation capability'),('transfusion','Harmony Health Hub transfusion navigation capability'),('claims','Harmony Health Hub claims navigation capability'),('reports','Harmony Health Hub reports navigation capability'),('report_submissions','Harmony Health Hub report submissions navigation capability'),('accounts_approvals','Harmony Health Hub accounts approvals navigation capability'),('tariff_adjustments','Harmony Health Hub tariff adjustments navigation capability'),('department_queue','Harmony Health Hub department queue navigation capability'),('laboratory','Harmony Health Hub laboratory navigation capability'),('radiology','Harmony Health Hub radiology navigation capability'),('radiology_results','Harmony Health Hub radiology results navigation capability'),('pharmacy','Harmony Health Hub pharmacy navigation capability'),('medication_administration','Harmony Health Hub medication administration navigation capability'),('billing','Harmony Health Hub billing navigation capability'),('maternity','Harmony Health Hub maternity navigation capability'),('telemedicine','Harmony Health Hub telemedicine navigation capability'),('fertility','Harmony Health Hub fertility navigation capability'),('dental','Harmony Health Hub dental navigation capability'),('procedures','Harmony Health Hub procedures navigation capability'),('anesthesia','Harmony Health Hub anesthesia navigation capability'),('ophthalmology','Harmony Health Hub ophthalmology navigation capability'),('ai_clinical','Harmony Health Hub ai clinical navigation capability'),('users','Harmony Health Hub users navigation capability'),('system_library','Harmony Health Hub system library navigation capability'),('offline_sync','Harmony Health Hub offline sync navigation capability'),('data_import','Harmony Health Hub data import navigation capability'),('inpatients','Harmony Health Hub inpatients navigation capability'),('meal_orders','Harmony Health Hub meal orders navigation capability'),('notifications','Harmony Health Hub notifications navigation capability'),('outside_lab','Harmony Health Hub outside lab navigation capability'),('financial_reports','Harmony Health Hub financial reports navigation capability'),('inventory','Harmony Health Hub inventory navigation capability'),('stock_alerts','Harmony Health Hub stock alerts navigation capability'),('patient_portal','Harmony Health Hub patient portal navigation capability'),('orders','Harmony Health Hub orders navigation capability'),('dietary_plans','Harmony Health Hub dietary plans navigation capability')
ON CONFLICT(permission_key) DO UPDATE SET description=EXCLUDED.description;

INSERT INTO public.role_permissions(role,permission_key)
VALUES
  ('admin','dashboard'),
  ('admin','patients'),
  ('admin','registration'),
  ('admin','appointments'),
  ('admin','triage'),
  ('admin','encounters'),
  ('admin','clinical_operations'),
  ('admin','ward'),
  ('admin','handover'),
  ('admin','emergency'),
  ('admin','theatre'),
  ('admin','transfusion'),
  ('admin','claims'),
  ('admin','reports'),
  ('admin','report_submissions'),
  ('admin','accounts_approvals'),
  ('admin','tariff_adjustments'),
  ('admin','department_queue'),
  ('admin','laboratory'),
  ('admin','radiology'),
  ('admin','radiology_results'),
  ('admin','pharmacy'),
  ('admin','medication_administration'),
  ('admin','billing'),
  ('admin','maternity'),
  ('admin','telemedicine'),
  ('admin','fertility'),
  ('admin','dental'),
  ('admin','procedures'),
  ('admin','anesthesia'),
  ('admin','ophthalmology'),
  ('admin','ai_clinical'),
  ('admin','users'),
  ('admin','system_library'),
  ('admin','offline_sync'),
  ('admin','data_import'),
  ('admin','inpatients'),
  ('admin','meal_orders'),
  ('admin','notifications'),
  ('admin','outside_lab'),
  ('admin','financial_reports'),
  ('admin','inventory'),
  ('admin','stock_alerts'),
  ('admin','patient_portal'),
  ('admin','orders'),
  ('admin','dietary_plans'),
  ('practitioner','dashboard'),
  ('practitioner','appointments'),
  ('practitioner','patients'),
  ('practitioner','encounters'),
  ('practitioner','clinical_operations'),
  ('practitioner','emergency'),
  ('practitioner','theatre'),
  ('practitioner','transfusion'),
  ('practitioner','department_queue'),
  ('practitioner','radiology'),
  ('practitioner','radiology_results'),
  ('practitioner','dental'),
  ('practitioner','procedures'),
  ('practitioner','anesthesia'),
  ('practitioner','laboratory'),
  ('practitioner','pharmacy'),
  ('practitioner','medication_administration'),
  ('practitioner','telemedicine'),
  ('practitioner','fertility'),
  ('practitioner','ophthalmology'),
  ('practitioner','ai_clinical'),
  ('nurse','dashboard'),
  ('nurse','patients'),
  ('nurse','triage'),
  ('nurse','encounters'),
  ('nurse','clinical_operations'),
  ('nurse','ward'),
  ('nurse','handover'),
  ('nurse','emergency'),
  ('nurse','theatre'),
  ('nurse','transfusion'),
  ('nurse','inpatients'),
  ('nurse','medication_administration'),
  ('nurse','meal_orders'),
  ('specialist_nurse','dashboard'),
  ('specialist_nurse','patients'),
  ('specialist_nurse','appointments'),
  ('specialist_nurse','triage'),
  ('specialist_nurse','encounters'),
  ('specialist_nurse','clinical_operations'),
  ('specialist_nurse','ward'),
  ('specialist_nurse','handover'),
  ('specialist_nurse','emergency'),
  ('specialist_nurse','theatre'),
  ('specialist_nurse','transfusion'),
  ('specialist_nurse','inpatients'),
  ('specialist_nurse','medication_administration'),
  ('specialist_nurse','ai_clinical'),
  ('midwife','dashboard'),
  ('midwife','maternity'),
  ('midwife','fertility'),
  ('midwife','inpatients'),
  ('midwife','clinical_operations'),
  ('midwife','handover'),
  ('midwife','emergency'),
  ('midwife','theatre'),
  ('midwife','transfusion'),
  ('midwife','triage'),
  ('midwife','medication_administration'),
  ('radiologist','dashboard'),
  ('radiologist','radiology'),
  ('radiologist','department_queue'),
  ('radiologist','patients'),
  ('radiologist','notifications'),
  ('radiologist','ai_clinical'),
  ('front_desk','dashboard'),
  ('front_desk','patients'),
  ('front_desk','registration'),
  ('front_desk','appointments'),
  ('front_desk','triage'),
  ('front_desk','clinical_operations'),
  ('front_desk','billing'),
  ('accountant','dashboard'),
  ('accountant','billing'),
  ('accountant','tariff_adjustments'),
  ('accountant','claims'),
  ('accountant','accounts_approvals'),
  ('accountant','clinical_operations'),
  ('accountant','financial_reports'),
  ('lab_technician','dashboard'),
  ('lab_technician','department_queue'),
  ('lab_technician','laboratory'),
  ('lab_technician','outside_lab'),
  ('lab_technician','reports'),
  ('pharmacist','dashboard'),
  ('pharmacist','department_queue'),
  ('pharmacist','pharmacy'),
  ('pharmacist','medication_administration'),
  ('pharmacist','inventory'),
  ('pharmacist','stock_alerts'),
  ('canteen','dashboard'),
  ('canteen','meal_orders'),
  ('canteen','orders'),
  ('canteen','dietary_plans'),
  ('patient','dashboard'),
  ('patient','patient_portal'),
  ('patient','appointments'),
  ('patient','telemedicine'),
  ('patient','billing')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_my_permissions()
RETURNS TABLE(permission_key TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public
AS $$
  SELECT rp.permission_key
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.permission_key=rp.permission_key
  JOIN public.user_roles ur ON ur.role=rp.role
  WHERE ur.user_id=auth.uid() AND p.is_active
  ORDER BY rp.permission_key;
$$;

REVOKE ALL ON FUNCTION public.get_my_permissions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_permissions() TO authenticated;
