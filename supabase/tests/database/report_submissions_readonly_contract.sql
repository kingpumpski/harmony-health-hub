BEGIN;

SELECT plan(7);

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.report_submissions'::regclass),
  'report submissions retain row-level security'
);
SELECT ok(
  has_table_privilege('authenticated', 'public.report_submissions', 'SELECT'),
  'authenticated users retain the read permission required by the Reports Center'
);
SELECT ok(
  NOT has_table_privilege('anon', 'public.report_submissions', 'SELECT'),
  'anonymous users cannot read report submissions'
);
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.report_submissions', 'INSERT'),
  'authenticated users cannot insert report submissions directly'
);
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.report_submissions', 'UPDATE'),
  'authenticated users cannot update report submissions directly'
);
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.report_submissions', 'DELETE'),
  'authenticated users cannot delete report submissions directly'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.report_submissions'::regclass
      AND polname = 'submissions_access'
      AND polcmd = 'r'
  ),
  'facility-scoped submission read policy remains available'
);

SELECT * FROM finish();
ROLLBACK;
