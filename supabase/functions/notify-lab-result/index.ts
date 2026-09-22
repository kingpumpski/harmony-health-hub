import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  const cors = buildCorsHeaders(req);
  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace(/^Bearer\s+/i, '');
    if (!token) {
      return new Response(JSON.stringify({ error: 'Authentication required' }), {
        status: 401,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const authClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: `Bearer ${token}` } } },
    );
    const { data: { user }, error: authError } = await authClient.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Authentication required' }), {
        status: 401,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const db = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    const { data: roles, error: roleError } = await db
      .from('user_roles')
      .select('role')
      .eq('user_id', user.id);
    const allowedRoles = ['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'lab_technician'];
    if (roleError || !roles?.some((row) => allowedRoles.includes(String(row.role)))) {
      return new Response(JSON.stringify({ error: 'Forbidden' }), {
        status: 403,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const body = await req.json();
    const patientEmail = String(body?.patientEmail ?? '').trim();
    const patientName = String(body?.patientName ?? '').trim();
    const testName = String(body?.testName ?? '').trim();
    if (!patientEmail || !patientName || !testName) {
      return new Response(JSON.stringify({ error: 'patientEmail, patientName and testName are required' }), {
        status: 400,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(patientEmail)) {
      return new Response(JSON.stringify({ error: 'Invalid patient email' }), {
        status: 400,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    // Email delivery is not configured yet. Do not echo patient contact data in the response.
    console.log(`[notify-lab-result] notification requested for test "${testName}"`);
    return new Response(JSON.stringify({ queued: false, deliveryConfigured: false }), {
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});
