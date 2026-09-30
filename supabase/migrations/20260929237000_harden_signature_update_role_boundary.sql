DROP POLICY IF EXISTS "signature owner update" ON public.user_document_signatures;
CREATE POLICY "signature owner update" ON public.user_document_signatures FOR UPDATE TO authenticated USING (
  (select auth.uid())=user_id AND (
    public.has_role((select auth.uid()),'admin') OR public.has_role((select auth.uid()),'it_admin') OR public.has_role((select auth.uid()),'practitioner') OR public.has_role((select auth.uid()),'nurse') OR public.has_role((select auth.uid()),'midwife') OR public.has_role((select auth.uid()),'specialist_nurse') OR public.has_role((select auth.uid()),'lab_technician') OR public.has_role((select auth.uid()),'radiologist') OR public.has_role((select auth.uid()),'radiology_technician') OR public.has_role((select auth.uid()),'pharmacist')
  )
) WITH CHECK (
  (select auth.uid())=user_id AND (
    public.has_role((select auth.uid()),'admin') OR public.has_role((select auth.uid()),'it_admin') OR public.has_role((select auth.uid()),'practitioner') OR public.has_role((select auth.uid()),'nurse') OR public.has_role((select auth.uid()),'midwife') OR public.has_role((select auth.uid()),'specialist_nurse') OR public.has_role((select auth.uid()),'lab_technician') OR public.has_role((select auth.uid()),'radiologist') OR public.has_role((select auth.uid()),'radiology_technician') OR public.has_role((select auth.uid()),'pharmacist')
  )
);