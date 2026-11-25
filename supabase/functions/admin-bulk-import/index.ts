import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';
import { requireAdmin } from '../_shared/admin-user-provisioning.ts';

const IMPORT_ENTITIES = new Set(['patients', 'pharmacy_inventory', 'icd_codes']);
const MAX_ROWS = 1000; // per request; the client sends large files in chunks
const json = (body: unknown, status: number, cors: Record<string, string>) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

const str = (v: unknown) => (v === null || v === undefined ? '' : String(v).trim());
const opt = (v: unknown) => (str(v) === '' ? null : str(v));
const isTransient = (msg: string) => /fetch failed|network|timeout|timed out|ECONNRESET|503|502|504|too many|rate limit|connection/i.test(msg);
const errMsg = (e: unknown) => (e instanceof Error ? e.message : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : String(e));

async function retry<T>(fn: () => Promise<T>, attempts = 3): Promise<T> {
  let last: unknown;
  for (let i = 0; i < attempts; i++) {
    try { return await fn(); } catch (e) {
      last = e; if (i === attempts - 1 || !isTransient(errMsg(e))) break;
      await new Promise((r) => setTimeout(r, 400 * 2 ** i));
    }
  }
  throw last;
}

Deno.serve(async (req) => {
  const pre = handlePreflight(req); if (pre) return pre;
  const cors = buildCorsHeaders(req);
  try {
    const auth = req.headers.get('Authorization');
    if (!auth) return json({ error: 'Authentication required' }, 401, cors);
    const service = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const token = auth.replace(/^Bearer\s+/i, '');
    const caller = await requireAdmin(service, token);
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const body = await req.json().catch(() => null);
    if (body?.action !== 'import_rows') return json({ error: 'Unsupported action' }, 400, cors);
    const entity = str(body?.entity);
    const rows: Record<string, unknown>[] = Array.isArray(body?.rows) ? body.rows : [];
    const filename = opt(body?.filename);
    const sourceFormat = ['csv', 'xlsx', 'xls'].includes(str(body?.source_format)) ? str(body.source_format) : 'csv';
    const recordJob = body?.record_job !== false;
    if (!IMPORT_ENTITIES.has(entity)) return json({ error: 'Unsupported import entity' }, 400, cors);
    if (!rows.length || rows.length > MAX_ROWS) return json({ error: `Each batch must contain 1-${MAX_ROWS} rows` }, 400, cors);

    const errors: { row: number; reason: string }[] = [];
    const skipped: { row: number; reason: string }[] = [];
    let inserted = 0;

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i] ?? {};
      const rowNo = Number(row.__row) || i + 2;
      try {
        if (entity === 'patients') {
          if (!str(row.first_name) || !str(row.last_name)) throw new Error('first_name and last_name are required');
          if (row.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(str(row.email))) throw new Error('invalid email');
          // Duplicate protection against existing records
          if (str(row.ghana_card_number)) {
            const { data } = await retry(async () => { const r = await db.from('patients').select('id,patient_code').eq('ghana_card_number', str(row.ghana_card_number)).limit(1); if (r.error) throw r.error; return r; });
            if (data?.length) { skipped.push({ row: rowNo, reason: `Already registered (Ghana Card) as ${data[0].patient_code ?? data[0].id}` }); continue; }
          }
          if (str(row.date_of_birth) || str(row.phone)) {
            let q = db.from('patients').select('id,patient_code').ilike('first_name', str(row.first_name)).ilike('last_name', str(row.last_name));
            q = str(row.date_of_birth) ? q.eq('date_of_birth', str(row.date_of_birth)) : q.eq('phone', str(row.phone));
            const { data } = await retry(async () => { const r = await q.limit(1); if (r.error) throw r.error; return r; });
            if (data?.length) { skipped.push({ row: rowNo, reason: `Patient already exists as ${data[0].patient_code ?? data[0].id}` }); continue; }
          }
          const patient: Record<string, unknown> = {};
          for (const [k, v] of Object.entries(row)) if (k !== '__row' && k !== 'created_by' && v !== null && v !== '') patient[k] = v;
          await retry(async () => { const { error } = await db.rpc('register_patient_workflow', { _patient: patient }); if (error) throw error; });
        } else if (entity === 'pharmacy_inventory') {
          if (!str(row.drug_name)) throw new Error('drug_name is required');
          const qty = Number(row.stock_quantity ?? 0); const price = Number(row.unit_price ?? 0); const reorder = Number(row.reorder_level ?? 20);
          if (![qty, price, reorder].every((n) => Number.isFinite(n) && n >= 0)) throw new Error('stock_quantity, unit_price and reorder_level must be 0 or more');
          let q = db.from('pharmacy_inventory').select('id').ilike('drug_name', str(row.drug_name));
          q = str(row.strength) ? q.ilike('strength', str(row.strength)) : q.is('strength', null);
          q = str(row.form) ? q.ilike('form', str(row.form)) : q;
          const { data: existing } = await retry(async () => { const r = await q.limit(1); if (r.error) throw r.error; return r; });
          if (existing?.length && !str(row.batch_number)) { skipped.push({ row: rowNo, reason: 'Drug with the same name/strength/form already in inventory — use a Goods Receipt to add stock' }); continue; }
          await retry(async () => {
            const { error } = await db.rpc('create_pharmacy_inventory_item', {
              _drug_name: str(row.drug_name), _brand_name: opt(row.brand_name), _generic_name: opt(row.generic_name),
              _strength: opt(row.strength), _form: opt(row.form), _supplier: opt(row.supplier), _batch_number: opt(row.batch_number),
              _expiry_date: opt(row.expiry_date), _stock_quantity: qty, _reorder_level: reorder, _unit_price: price,
            });
            if (error) throw error;
          });
        } else {
          const code = str(row.code).toUpperCase();
          if (!code || !str(row.description)) throw new Error('code and description are required');
          const { data: existing } = await retry(async () => { const r = await db.from('icd_codes').select('id').eq('code', code).limit(1); if (r.error) throw r.error; return r; });
          if (existing?.length) { skipped.push({ row: rowNo, reason: `ICD code ${code} already exists` }); continue; }
          await retry(async () => {
            const { error } = await db.rpc('create_icd_code_workflow', { _code: code, _description: str(row.description), _version: opt(row.version) ?? 'ICD-10', _category: opt(row.category) });
            if (error) throw error;
          });
        }
        inserted++;
      } catch (e) {
        const m = errMsg(e);
        errors.push({ row: rowNo, reason: /duplicate key|unique/i.test(m) ? 'Already exists (duplicate)' : m });
      }
    }

    if (recordJob) {
      const status = inserted === 0 && errors.length ? 'failed' : errors.length ? 'completed_with_errors' : 'completed';
      const { error: jobErr } = await service.from('bulk_import_jobs').insert({
        entity_type: entity, source_format: sourceFormat, file_name: filename, total_rows: rows.length,
        successful_rows: inserted, failed_rows: errors.length, errors: [...errors, ...skipped.map((s) => ({ ...s, skipped: true }))],
        status, created_by: caller.id, completed_at: new Date().toISOString(),
      });
      if (jobErr) console.error('bulk_import_jobs insert failed', jobErr.message);
      await service.rpc('record_system_audit', {
        _action: 'admin_bulk_import', _module: 'administration', _entity_type: entity, _severity: errors.length ? 'warning' : 'info',
        _metadata: { filename, source_format: sourceFormat, total_rows: rows.length, successful_rows: inserted, skipped_rows: skipped.length, failed_rows: errors.length },
      }).then(() => undefined, () => undefined);
    }
    return json({ ok: true, entity, total_rows: rows.length, inserted_rows: inserted, skipped_rows: skipped.length, failed_rows: errors.length, errors, skipped }, 200, cors);
  } catch (e) {
    const message = errMsg(e);
    const status = message === 'Invalid authentication' ? 401 : message === 'Administrator access required' ? 403 : 500;
    return json({ error: message }, status, cors);
  }
});
