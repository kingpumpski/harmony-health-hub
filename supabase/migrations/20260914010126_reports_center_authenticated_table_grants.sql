-- Keep the repository migration history aligned with the production Reports Center grants.
-- RLS remains authoritative for row-level access; these grants only permit the
-- authenticated role to reach the tables through PostgREST/Supabase clients.

GRANT USAGE ON SCHEMA public TO authenticated;

GRANT SELECT ON TABLE
  public.healthcare_facilities,
  public.facility_memberships,
  public.report_categories,
  public.report_definitions,
  public.facility_report_config,
  public.report_generation_runs,
  public.report_generation_items,
  public.report_submissions
TO authenticated;

GRANT INSERT, UPDATE ON TABLE
  public.facility_report_config,
  public.report_generation_runs,
  public.report_generation_items,
  public.report_submissions
TO authenticated;
