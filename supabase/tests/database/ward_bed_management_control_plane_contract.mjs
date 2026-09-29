import fs from 'node:fs';
import path from 'node:path';

const migrationsDir = path.join(process.cwd(), 'supabase/migrations');
const files = [
  '20260929080000_ward_bed_management_control_plane.sql',
  '20260929081500_ward_management_facility_selection.sql',
  '20260929083000_ward_management_workspace_read_surface.sql',
  '20260929170000_fix_ward_management_workspace_ordering.sql',
];
const source = files.map((name) => fs.readFileSync(path.join(migrationsDir, name), 'utf8')).join('\n');
const fixSource = fs.readFileSync(
  path.join(migrationsDir, '20260929170000_fix_ward_management_workspace_ordering.sql'),
  'utf8',
);

const required = [
  "CREATE OR REPLACE FUNCTION public.create_ward_unit(",
  "public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')",
  "INSERT INTO public.ward_units",
  "facility_id",
  "CREATE OR REPLACE FUNCTION public.create_ward_bed(",
  "Administrator or IT administrator role required",
  "INSERT INTO public.ward_beds",
  "get_ward_management_workspace",
  "assign_ward_unit_facility",
  "import_legacy_ward",
  "INSERT INTO public.ward_units(name,code,specialty,gender_policy,active,facility_id)",
];

const missing = required.filter((fragment) => !source.includes(fragment));
const hasFixedOrdering = fixSource.includes('ORDER BY is_legacy,name');
const hasBrokenOrdering = fixSource.includes('ORDER BY is_legacy,w.name');

if (missing.length || !hasFixedOrdering || hasBrokenOrdering) {
  console.error('Ward-bed management control-plane contract failed:');
  for (const fragment of missing) console.error(`- missing: ${fragment}`);
  if (!hasFixedOrdering) console.error('- missing: fixed ward ordering');
  if (hasBrokenOrdering) console.error('- forbidden in fix migration: ORDER BY is_legacy,w.name');
  process.exitCode = 1;
} else {
  console.log(`Ward-bed management control-plane contract: ${required.length}/${required.length} invariants present; ordering regression fixed`);
}
