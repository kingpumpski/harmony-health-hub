DROP POLICY IF EXISTS "signature owner read" ON public.user_document_signatures;
DROP POLICY IF EXISTS "signature owner insert" ON public.user_document_signatures;
DROP POLICY IF EXISTS "signature owner update" ON public.user_document_signatures;
CREATE POLICY "signature owner read" ON public.user_document_signatures FOR SELECT TO authenticated USING (
  (select auth.uid())=user_id AND (
    public.has_role((select auth.uid()),'admin'::public.app_role) OR public.has_role((select auth.uid()),'it_admin'::public.app_role) OR public.has_role((select auth.uid()),'practitioner'::public.app_role) OR public.has_role((select auth.uid()),'nurse'::public.app_role) OR public.has_role((select auth.uid()),'midwife'::public.app_role) OR public.has_role((select auth.uid()),'specialist_nurse'::public.app_role) OR public.has_role((select auth.uid()),'lab_technician'::public.app_role) OR public.has_role((select auth.uid()),'radiologist'::public.app_role) OR public.has_role((select auth.uid()),'radiology_technician'::public.app_role) OR public.has_role((select auth.uid()),'pharmacist'::public.app_role)
  )
);
CREATE POLICY "signature owner insert" ON public.user_document_signatures FOR INSERT TO authenticated WITH CHECK (
  (select auth.uid())=user_id AND (
    public.has_role((select auth.uid()),'admin'::public.app_role) OR public.has_role((select auth.uid()),'it_admin'::public.app_role) OR public.has_role((select auth.uid()),'practitioner'::public.app_role) OR public.has_role((select auth.uid()),'nurse'::public.app_role) OR public.has_role((select auth.uid()),'midwife'::public.app_role) OR public.has_role((select auth.uid()),'specialist_nurse'::public.app_role) OR public.has_role((select auth.uid()),'lab_technician'::public.app_role) OR public.has_role((select auth.uid()),'radiologist'::public.app_role) OR public.has_role((select auth.uid()),'radiology_technician'::public.app_role) OR public.has_role((select auth.uid()),'pharmacist'::public.app_role)
  )
);
CREATE POLICY "signature owner update" ON public.user_document_signatures FOR UPDATE TO authenticated USING (
  (select auth.uid())=user_id
) WITH CHECK (
  (select auth.uid())=user_id
);
