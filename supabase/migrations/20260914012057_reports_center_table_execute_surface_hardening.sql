-- Reports Center table execute-surface hardening.
--
-- Keep direct table access least-privilege and preserve RLS as the
-- authoritative row-level boundary. Facility creation remains behind the
-- protected create_reports_facility RPC.

REVOKE ALL ON TABLE
  public.healthcare_facilities,
  public.facility_memberships,
  public.report_categories,
  public.report_definitions,
  public.facility_report_config,
  public.report_generation_runs,
  public.report_generation_items,
  public.report_submissions
FROM anon;

REVOKE ALL ON TABLE
  public.healthcare_facilities,
  public.facility_memberships,
  public.report_categories,
  public.report_definitions,
  public.facility_report_config,
  public.report_generation_runs,
  public.report_generation_items,
  public.report_submissions
FROM authenticated;

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
