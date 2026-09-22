import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

const ALLOWED_ROLES = new Set(['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'lab_technician']);

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  const cors = buildCorsHeaders(req);
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Authentication required' }, 401);
    const token = authHeader.replace(/^Bearer\s+/i, '');

    const authClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: `Bearer ${token}` } } },
    );
    const { data: { user }, error: authError } = await authClient.auth.getUser(token);
    if (authError || !user) return json({ error: 'Authentication required' }, 401);

    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: roles, error: roleError } = await db.from('user_roles').select('role').eq('user_id', user.id);
    if (roleError || !roles?.some((row) => ALLOWED_ROLES.has(String(row.role)))) {
      return json({ error: 'Forbidden' }, 403);
    }

    const body = await req.json();
    const labOrderId = String(body?.labOrderId ?? '').trim();
    if (!labOrderId) return json({ error: 'Lab order id is required' }, 400);

    const { data: order, error: orderError } = await db
      .from('lab_orders')
      .select('id,patient_id,test_name,status')
      .eq('id', labOrderId)
      .maybeSingle();
    if (orderError || !order) return json({ error: 'Lab order not found' }, 404);
    if (order.status !== 'approved') return json({ error: 'Lab result is not approved' }, 409);

    const { data: patient, error: patientError } = await db
      .from('patients')
      .select('id,email,first_name,last_name')
      .eq('id', order.patient_id)
      .maybeSingle();
    if (patientError || !patient) return json({ error: 'Patient not found' }, 404);

    if (!patient.email) {
      return json({ queued: false, reason: 'Patient email unavailable', testName: order.test_name });
    }

    console.log(`[notify-lab-result] would email patient ${patient.id} about ${order.test_name}`);
    return json({ queued: true, testName: order.test_name });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
