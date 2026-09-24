import fs from 'node:fs';

const files = {
  draft: fs.readFileSync('supabase/migrations/20260920222100_ai_protocol_draft_creation.sql','utf8'),
  lifecycle: fs.readFileSync('supabase/migrations/20260920222000_ai_protocol_lifecycle_hardening.sql','utf8'),
  workspace: fs.readFileSync('supabase/migrations/20260920221000_ai_workspace_least_privilege.sql','utf8'),
};

const checks = [
  ['protocol draft uses has_role', files.draft.includes("public.has_role(auth.uid(),'admin')") && files.draft.includes("public.has_role(auth.uid(),'practitioner')")],
  ['protocol lifecycle uses has_role', files.lifecycle.includes("public.has_role(auth.uid(),'admin')") && files.lifecycle.includes("public.has_role(auth.uid(),'practitioner')")],
  ['case memory uses complete role union', files.workspace.includes("public.has_role(auth.uid(),'nurse')") && files.workspace.includes("public.has_role(auth.uid(),'pharmacist')")],
  ['report requests uses complete staff role union', files.workspace.includes("public.has_role(auth.uid(),'radiologist')") && files.workspace.includes("public.has_role(auth.uid(),'specialist_nurse')")],
  ['legacy profiles role lookup absent', !files.draft.includes('FROM public.profiles') && !files.lifecycle.includes('FROM public.profiles') && !files.workspace.includes('FROM public.profiles')],
  ['legacy single-role variable absent', !files.draft.includes('v_role') && !files.lifecycle.includes('v_role') && !files.workspace.includes('v_role')],
];

for (const [name, ok] of checks) if (!ok) throw new Error('AI authorization contract failed: '+name);
console.log('AI multi-role authorization contract passed');
