CREATE OR REPLACE FUNCTION public.is_staff_member(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role <> 'patient')
$$;
REVOKE ALL ON FUNCTION public.is_staff_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_staff_member(uuid) TO authenticated;

DROP POLICY IF EXISTS "stg_read_all" ON public.stg_guidelines;
CREATE POLICY "stg_staff_read" ON public.stg_guidelines FOR SELECT TO authenticated USING (public.is_staff_member(auth.uid()));
DROP POLICY IF EXISTS "clinical_read" ON public.icd_codes;
DROP POLICY IF EXISTS "icd_read_all" ON public.icd_codes;
CREATE POLICY "icd_staff_read" ON public.icd_codes FOR SELECT TO authenticated USING (public.is_staff_member(auth.uid()));
DROP POLICY IF EXISTS "Anyone signed in can read settings" ON public.facility_settings;
CREATE POLICY "Staff read settings" ON public.facility_settings FOR SELECT TO authenticated USING (public.is_staff_member(auth.uid()));
DROP POLICY IF EXISTS "Staff read lab params" ON public.lab_test_parameters;
CREATE POLICY "Staff read lab params" ON public.lab_test_parameters FOR SELECT TO authenticated USING (public.is_staff_member(auth.uid()));
DROP POLICY IF EXISTS "Staff read lab catalog" ON public.lab_test_catalog;
CREATE POLICY "Staff read lab catalog" ON public.lab_test_catalog FOR SELECT TO authenticated USING (public.is_staff_member(auth.uid()));

DROP POLICY IF EXISTS "admins manage roles" ON public.user_roles;
CREATE POLICY "admins manage roles" ON public.user_roles FOR ALL TO authenticated
USING (public.has_role(auth.uid(), 'system_superuser') OR (public.has_role(auth.uid(), 'admin') AND role NOT IN ('system_superuser','admin')))
WITH CHECK (public.has_role(auth.uid(), 'system_superuser') OR (public.has_role(auth.uid(), 'admin') AND role NOT IN ('system_superuser','admin') AND user_id <> auth.uid()));