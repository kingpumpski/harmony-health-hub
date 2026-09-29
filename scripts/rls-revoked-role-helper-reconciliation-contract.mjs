#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
const p=path.join(process.cwd(),'supabase/migrations/20260929214500_reconcile_revoked_role_helper_rls_policies.sql');
const sql=fs.readFileSync(p,'utf8');
const policies=['clinical_reference_admin_insert','clinical_reference_admin_update','clinical_reference_read','insurance_companies_admin_it_read','insurance_service_tariffs_admin_delete','insurance_service_tariffs_admin_insert','insurance_service_tariffs_admin_read','insurance_service_tariffs_admin_update','canteen_operations_broadcast_read','clinical staff read patient documents storage','outside lab storage delete','outside lab storage read','outside lab storage upload'];
for(const name of policies){if(!sql.toLowerCase().includes(name.toLowerCase()))throw new Error('Missing policy: '+name);}
if(/\b(has_role|is_clinical_staff)\s*\(/i.test(sql))throw new Error('Legacy direct role helper remains');
if(!sql.includes('current_user_has_role')||!sql.includes('current_user_is_clinical_staff'))throw new Error('Secure wrapper missing');
console.log(`Verified ${policies.length} revoked-helper RLS policy reconciliations.`);
