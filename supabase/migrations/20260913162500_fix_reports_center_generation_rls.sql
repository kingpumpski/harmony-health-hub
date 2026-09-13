DROP POLICY IF EXISTS report_generation_items_insert ON public.report_generation_items;
CREATE POLICY report_generation_items_insert ON public.report_generation_items FOR INSERT TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.report_generation_runs r
    WHERE r.id = run_id
      AND public.has_facility_access((select auth.uid()), r.facility_id)
  )
);
