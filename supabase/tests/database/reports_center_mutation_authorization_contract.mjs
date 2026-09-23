import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20260914010028_reports_center_production_reconciliation.sql', 'utf8');

const checks = [
  ['run updates are creator/admin scoped', /CREATE POLICY reports_runs_update ON public\.report_generation_runs FOR UPDATE TO authenticated USING\(created_by=auth\.uid\(\) OR public\.has_role\(auth\.uid\(\),'admin'\)\) WITH CHECK\(created_by=auth\.uid\(\) OR public\.has_role\(auth\.uid\(\),'admin'\)\)/],
  ['run inserts bind creator', /CREATE POLICY reports_runs_insert ON public\.report_generation_runs FOR INSERT TO authenticated WITH CHECK\(public\.has_facility_access\(auth\.uid\(\),facility_id\) AND created_by=auth\.uid\(\)\)/],
  ['item updates are creator/admin scoped', /CREATE POLICY reports_items_update ON public\.report_generation_items FOR UPDATE TO authenticated/],
  ['submission updates are facility scoped', /CREATE POLICY reports_submissions_update ON public\.report_submissions FOR UPDATE TO authenticated USING\(public\.has_facility_access/],
  ['submission insert binds submitted_by', /reports_submissions_insert[\\s\\S]*submitted_by IS NULL OR submitted_by=auth\\.uid\\(\\)/],
  ['submission update requires matching submitter or admin', /reports_submissions_update[\\s\\S]*submitted_by IS NULL OR submitted_by=auth\\.uid\\(\\) OR public\\.has_role\\(auth\\.uid\\(\\),'admin'\\)/],  ['protected submission RPC execute revoked from public', /REVOKE ALL ON FUNCTION public\.mark_report_submissions_submitted\(UUID\[\]\) FROM PUBLIC/],
  ['protected submission RPC execute granted to authenticated', /GRANT EXECUTE ON FUNCTION public\.mark_report_submissions_submitted\(UUID\[\]\) TO authenticated/],
  ['stale-run RPC execute revoked from public', /REVOKE ALL ON FUNCTION public\.recover_stale_report_run\(UUID,INTEGER\) FROM PUBLIC/],
  ['submission tracking RPC execute revoked from public', /REVOKE ALL ON FUNCTION public\.upsert_report_submission_tracking\(UUID,UUID,DATE,DATE,DATE,JSONB\) FROM PUBLIC/]
];

for (const [name, pattern] of checks) {
  if (!pattern.test(migration)) throw new Error('Reports Center mutation authorization contract failed: ' + name);
}

console.log('Reports Center mutation authorization contract passed');
