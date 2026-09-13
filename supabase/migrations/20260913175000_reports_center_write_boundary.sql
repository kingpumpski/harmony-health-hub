-- Keep report generation and submission state changes server-authoritative.
-- Facility membership grants visibility, but should not grant arbitrary mutation of
-- generation accounting or submission lifecycle state.

DROP POLICY IF EXISTS report_generation_runs_update ON public.report_generation_runs;
CREATE POLICY report_generation_runs_update ON public.report_generation_runs
  FOR UPDATE TO authenticated
  USING (
    public.has_facility_access((select auth.uid()), facility_id)
    AND created_by = (select auth.uid())
  )
  WITH CHECK (
    public.has_facility_access((select auth.uid()), facility_id)
    AND created_by = (select auth.uid())
  );

DROP POLICY IF EXISTS report_generation_items_update ON public.report_generation_items;
CREATE POLICY report_generation_items_update ON public.report_generation_items
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.report_generation_runs r
      WHERE r.id = run_id
        AND public.has_facility_access((select auth.uid()), r.facility_id)
        AND r.created_by = (select auth.uid())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.report_generation_runs r
      WHERE r.id = run_id
        AND public.has_facility_access((select auth.uid()), r.facility_id)
        AND r.created_by = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS report_submissions_write ON public.report_submissions;

-- Submission creation/regeneration and lifecycle transitions are performed through
-- SECURITY DEFINER functions that enforce authentication and facility boundaries.
-- The table remains directly readable to authorized facility members.
