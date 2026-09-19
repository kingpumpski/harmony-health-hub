import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

const ALLOWED_ROLES = new Set(['admin','it_admin','practitioner','nurse','specialist_nurse','midwife','lab_technician','pharmacist','accountant','front_desk','canteen','radiologist','patient']);
const IMPORT_ENTITIES = new Set(['patients','pharmacy_inventory','icd_codes']);
const MAX_ROWS = 10000;

const json = (body: unknown, status: number, cors: Record<string,string>) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  const pre = handlePreflight(req); if (pre) return pre;
  const cors = buildCorsHeaders(req);
  try {
    const auth = req.headers.get('Authorization');
    if (!auth) return json({ error: 'Authentication required' }, 401, cors);
    const service = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const token = auth.replace(/^Bearer\s+/i, '');
    const { data: { user: caller }, error: authError } = await service.auth.getUser(token);
    if (authError || !caller) return json({ error: 'Invalid authentication' }, 401, cors);
    const { data: adminRole } = await service.from('user_roles').select('role').eq('user_id', caller.id).eq('role', 'admin').maybeSingle();
    if (!adminRole) return json({ error: 'Administrator access required' }, 403, cors);

    const body = await req.json();
    const action = String(body?.action ?? '');

    if (action === 'import_rows') {
      const entity = String(body?.entity ?? '');
      const rows = Array.isArray(body?.rows) ? body.rows : [];
      const filename = body?.filename ? String(body.filename) : null;
      if (!IMPORT_ENTITIES.has(entity)) return json({ error: 'Unsupported import entity' }, 400, cors);
      if (!rows.length || rows.length > MAX_ROWS) return json({ error: 'Import must contain 1-' + MAX_ROWS + ' rows' }, 400, cors);
      const errors: { row: number; reason: string }[] = [];
      let inserted = 0;
      for (let i = 0; i < rows.length; i++) {
        const row = rows[i] ?? {};
        try {
          if (entity === 'patients') {
            if (!String(row.first_name ?? '').trim() || !String(row.last_name ?? '').trim()) throw new Error('first_name and last_name are required');
            if (row.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(row.email))) throw new Error('invalid email');
            await service.from('patients').insert({ ...row, created_by: caller.id }).throwOnError();
          } else if (entity === 'pharmacy_inventory') {
            if (!String(row.drug_name ?? '').trim()) throw new Error('drug_name is required');
            await service.from('pharmacy_inventory').insert({
              drug_name: String(row.drug_name), generic_name: row.generic_name ?? null, strength: row.strength ?? null,
              form: row.form ?? null, stock_quantity: Number(row.stock_quantity ?? 0), reorder_level: Number(row.reorder_level ?? 20),
              unit_price: Number(row.unit_price ?? 0), supplier: row.supplier ?? null, expiry_date: row.expiry_date ?? null,
            }).throwOnError();
          } else {
            if (!String(row.code ?? '').trim() || !String(row.description ?? '').trim()) throw new Error('code and description are required');
            await service.from('icd_codes').insert({ code: String(row.code), description: String(row.description), version: row.version ?? 'ICD-10', category: row.category ?? null }).throwOnError();
          }
          inserted++;
        } catch (e) { errors.push({ row: i + 2, reason: e instanceof Error ? e.message : String(e) }); }
      }
      const status = inserted === 0 ? 'failed' : errors.length ? 'completed_with_errors' : 'completed';
      await service.from('bulk_import_jobs').insert({
        entity_type: entity, source_format: 'csv', file_name: filename, total_rows: rows.length,
        successful_rows: inserted, failed_rows: errors.length, errors, status, created_by: caller.id, completed_at: new Date().toISOString(),
      });
      await service.rpc('record_system_audit', {
        _action: 'admin_bulk_import', _module: 'administration', _entity_type: entity,
        _severity: errors.length ? 'warning' : 'info',
        _metadata: { filename, total_rows: rows.length, successful_rows: inserted, failed_rows: errors.length },
      });
      return json({ ok: true, entity, total_rows: rows.length, inserted_rows: inserted, failed_rows: errors.length, errors }, 200, cors);
    }

    if (action === 'bulk_create_users') {
      const rows = Array.isArray(body?.rows) ? body.rows : [];
      if (!rows.length || rows.length > 500) return json({ error: 'Staff import must contain 1-500 rows' }, 400, cors);
      const results: { row: number; email?: string; user_id?: string; status: 'created'|'failed'; error?: string }[] = [];
      for (let i = 0; i < rows.length; i++) {
        const row = rows[i] ?? {};
        let createdId: string | null = null;
        try {
          const email = String(row.email ?? '').trim().toLowerCase();
          const firstName = String(row.first_name ?? row.firstName ?? '').trim();
          const lastName = String(row.last_name ?? row.lastName ?? '').trim();
          const role = String(row.role ?? 'patient').trim().toLowerCase();
          const onboarding = String(row.onboarding ?? 'invite') === 'password' ? 'password' : 'invite';
          const password = String(row.password ?? '');
          if (!email.includes('@') || !firstName || !lastName) throw new Error('email, first_name and last_name are required');
          if (!ALLOWED_ROLES.has(role)) throw new Error('unsupported role');
          if (onboarding === 'password' && password.length < 8) throw new Error('password onboarding requires at least 8 characters');
          const metadata = { first_name: firstName, last_name: lastName, phone: String(row.phone ?? ''), department: String(row.department ?? ''), specialization: String(row.specialization ?? '') };
          const created = onboarding === 'password'
            ? await service.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: metadata })
            : await service.auth.admin.inviteUserByEmail(email, { data: metadata });
          if (created.error || !created.data.user) throw new Error(created.error?.message ?? 'Unable to create authenticated user');
          createdId = created.data.user.id;
          const profile = await service.from('profiles').upsert({
            id: createdId, email, first_name: firstName, last_name: lastName, phone: metadata.phone || null,
            department: metadata.department || null, specialization: metadata.specialization || null,
          }, { onConflict: 'id' });
          if (profile.error) throw new Error('Profile creation failed: ' + profile.error.message);
          const roleDelete = await service.from('user_roles').delete().eq('user_id', createdId);
          if (roleDelete.error) throw new Error('Role initialization failed: ' + roleDelete.error.message);
          const roleInsert = await service.from('user_roles').insert({ user_id: createdId, role });
          if (roleInsert.error) throw new Error('Role assignment failed: ' + roleInsert.error.message);
          await service.rpc('record_system_audit', {
            _action: 'admin_bulk_create_user', _module: 'administration', _entity_type: 'user', _entity_id: createdId,
            _severity: 'info', _metadata: { email, role, onboarding, source_row: i + 2 },
          });
          results.push({ row: i + 2, email, user_id: createdId, status: 'created' });
        } catch (e) {
          if (createdId) await service.auth.admin.deleteUser(createdId);
          results.push({ row: i + 2, email: String(row.email ?? ''), status: 'failed', error: e instanceof Error ? e.message : String(e) });
        }
      }
      return json({ ok: true, total_rows: rows.length, created_rows: results.filter(r => r.status === 'created').length, failed_rows: results.filter(r => r.status === 'failed').length, results }, 200, cors);
    }
    return json({ error: 'Unsupported action' }, 400, cors);
  } catch (e) { return json({ error: e instanceof Error ? e.message : String(e) }, 500, cors); }
});
