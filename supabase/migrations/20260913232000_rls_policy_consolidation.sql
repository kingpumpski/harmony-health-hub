-- Consolidate overlapping permissive policies without changing authorization outcomes.

DROP POLICY IF EXISTS "staff manage admissions" ON public.admissions;
CREATE POLICY "staff insert admissions" ON public.admissions AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((select public.current_user_is_clinical_staff()));
CREATE POLICY "staff update admissions" ON public.admissions AS PERMISSIVE FOR UPDATE TO authenticated USING ((select public.current_user_is_clinical_staff())) WITH CHECK ((select public.current_user_is_clinical_staff()));
CREATE POLICY "staff delete admissions" ON public.admissions AS PERMISSIVE FOR DELETE TO authenticated USING ((select public.current_user_is_clinical_staff()));

DROP POLICY IF EXISTS "staff read appointments" ON public.appointments;

DROP POLICY IF EXISTS "patient reads own queue" ON public.department_queues;
DROP POLICY IF EXISTS "staff manage queues" ON public.department_queues;
DROP POLICY IF EXISTS "staff read queues" ON public.department_queues;
CREATE POLICY "authorized users read queues" ON public.department_queues AS PERMISSIVE FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.patients p WHERE p.id=department_queues.patient_id AND p.user_id=(select auth.uid()))
  OR (select public.current_user_is_clinical_staff())
  OR (select public.current_user_has_role('accountant'::public.app_role))
);
CREATE POLICY "staff insert queues" ON public.department_queues AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((select public.current_user_is_clinical_staff()) OR (select public.current_user_has_role('accountant'::public.app_role)));
CREATE POLICY "staff update queues" ON public.department_queues AS PERMISSIVE FOR UPDATE TO authenticated USING ((select public.current_user_is_clinical_staff()) OR (select public.current_user_has_role('accountant'::public.app_role))) WITH CHECK ((select public.current_user_is_clinical_staff()) OR (select public.current_user_has_role('accountant'::public.app_role)));
CREATE POLICY "staff delete queues" ON public.department_queues AS PERMISSIVE FOR DELETE TO authenticated USING ((select public.current_user_is_clinical_staff()) OR (select public.current_user_has_role('accountant'::public.app_role)));

DROP POLICY IF EXISTS "staff manage patient documents" ON public.patient_documents;
DROP POLICY IF EXISTS "staff read patient documents" ON public.patient_documents;
CREATE POLICY "authorized users read patient documents" ON public.patient_documents AS PERMISSIVE FOR SELECT TO authenticated USING ((select public.current_user_is_clinical_staff()) OR (select public.current_user_has_role('accountant'::public.app_role)));
CREATE POLICY "staff insert patient documents" ON public.patient_documents AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((select public.current_user_can_edit_patient_record()));
CREATE POLICY "staff update patient documents" ON public.patient_documents AS PERMISSIVE FOR UPDATE TO authenticated USING ((select public.current_user_can_edit_patient_record())) WITH CHECK ((select public.current_user_can_edit_patient_record()));
CREATE POLICY "staff delete patient documents" ON public.patient_documents AS PERMISSIVE FOR DELETE TO authenticated USING ((select public.current_user_can_edit_patient_record()));

DROP POLICY IF EXISTS "patients read own record" ON public.patients;
DROP POLICY IF EXISTS "staff manage patients" ON public.patients;
DROP POLICY IF EXISTS "staff read patients" ON public.patients;
DROP POLICY IF EXISTS "authorized staff update patients" ON public.patients;
CREATE POLICY "authorized users read patients" ON public.patients AS PERMISSIVE FOR SELECT TO authenticated USING (
  user_id=(select auth.uid()) OR (select public.current_user_is_clinical_staff()) OR (select public.current_user_has_role('accountant'::public.app_role))
);
CREATE POLICY "staff insert patients" ON public.patients AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((select public.current_user_is_clinical_staff()));
CREATE POLICY "staff update patients" ON public.patients AS PERMISSIVE FOR UPDATE TO authenticated USING ((select public.current_user_can_edit_patient_record())) WITH CHECK ((select public.current_user_can_edit_patient_record()));
CREATE POLICY "staff delete patients" ON public.patients AS PERMISSIVE FOR DELETE TO authenticated USING ((select public.current_user_is_clinical_staff()));

DROP POLICY IF EXISTS "admins manage profiles" ON public.profiles;
DROP POLICY IF EXISTS "staff read all profiles" ON public.profiles;
DROP POLICY IF EXISTS "users read own profile" ON public.profiles;
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "authorized users read profiles" ON public.profiles AS PERMISSIVE FOR SELECT TO authenticated USING (
  id=(select auth.uid()) OR (select public.current_user_is_clinical_staff()) OR (select public.current_user_has_role('accountant'::public.app_role))
);
CREATE POLICY "authorized users update profiles" ON public.profiles AS PERMISSIVE FOR UPDATE TO authenticated
  USING (id=(select auth.uid()) OR (select public.current_user_has_role('admin'::public.app_role)))
  WITH CHECK (id=(select auth.uid()) OR (select public.current_user_has_role('admin'::public.app_role)));
CREATE POLICY "admins insert profiles" ON public.profiles AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((select public.current_user_has_role('admin'::public.app_role)));
CREATE POLICY "admins delete profiles" ON public.profiles AS PERMISSIVE FOR DELETE TO authenticated USING ((select public.current_user_has_role('admin'::public.app_role)));

NOTIFY pgrst,'reload schema';