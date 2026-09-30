DROP POLICY IF EXISTS "signature owner read" ON public.user_document_signatures;
DROP POLICY IF EXISTS "signature owner insert" ON public.user_document_signatures;
DROP POLICY IF EXISTS "signature owner update" ON public.user_document_signatures;
CREATE POLICY "signature owner read" ON public.user_document_signatures FOR SELECT TO authenticated USING (
  (select auth.uid())=user_id AND (
    public.has_role((select auth.uid()),'admin') OR public.has_role((select auth.uid()),'it_admin') OR public.has_role((select auth.uid()),'practitioner') OR public.has_role((select auth.uid()),'nurse') OR public.has_role((select auth.uid()),'midwife') OR public.has_role((select auth.uid()),'specialist_nurse') OR public.has_role((select auth.uid()),'lab_technician') OR public.has_role((select auth.uid()),'radiologist') OR public.has_role((select auth.uid()),'radiology_technician') OR public.has_role((select auth.uid()),'pharmacist')
  )
);
CREATE POLICY "signature owner insert" ON public.user_document_signatures FOR INSERT TO authenticated WITH CHECK (
  (select auth.uid())=user_id AND (
    public.has_role((select auth.uid()),'admin') OR public.has_role((select auth.uid()),'it_admin') OR public.has_role((select auth.uid()),'practitioner') OR public.has_role((select auth.uid()),'nurse') OR public.has_role((select auth.uid()),'midwife') OR public.has_role((select auth.uid()),'specialist_nurse') OR public.has_role((select auth.uid()),'lab_technician') OR public.has_role((select auth.uid()),'radiologist') OR public.has_role((select auth.uid()),'radiology_technician') OR public.has_role((select auth.uid()),'pharmacist')
  )
);
CREATE POLICY "signature owner update" ON public.user_document_signatures FOR UPDATE TO authenticated USING (
  (select auth.uid())=user_id
) WITH CHECK (
  (select auth.uid())=user_id
);
