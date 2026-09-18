import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

const allowedRoles = new Set([
  'admin','practitioner','nurse','specialist_nurse','midwife','lab_technician',
  'pharmacist','accountant','front_desk','canteen','patient',
]);

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  const cors = buildCorsHeaders(req);
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Authentication required' }, 401);

    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    const token = authHeader.replace(/^Bearer\s+/i, '');
    const { data: { user: caller }, error: callerError } = await adminClient.auth.getUser(token);
    if (callerError || !caller) return json({ error: 'Invalid authentication' }, 401);

    const { data: callerRole } = await adminClient
      .from('user_roles')
      .select('role')
      .eq('user_id', caller.id)
      .eq('role', 'admin')
      .maybeSingle();
    if (!callerRole) return json({ error: 'Administrator access required' }, 403);

    const body = await req.json();
    const email = String(body?.email ?? '').trim().toLowerCase();
    const firstName = String(body?.firstName ?? '').trim();
    const lastName = String(body?.lastName ?? '').trim();
    const phone = String(body?.phone ?? '').trim();
    const department = String(body?.department ?? '').trim();
    const specialization = String(body?.specialization ?? '').trim();
    const role = String(body?.role ?? 'patient');
    const onboarding = body?.onboarding === 'password' ? 'password' : 'invite';
    const password = String(body?.password ?? '');

    if (!email || !email.includes('@')) return json({ error: 'A valid email is required' }, 400);
    if (!firstName || !lastName) return json({ error: 'First and last name are required' }, 400);
    if (!allowedRoles.has(role)) return json({ error: 'Unsupported role' }, 400);
    if (onboarding === 'password' && password.length < 8) {
      return json({ error: 'Password onboarding requires at least 8 characters' }, 400);
    }

    const metadata = { first_name: firstName, last_name: lastName, phone, department, specialization };
    const created = onboarding === 'invite'
      ? await adminClient.auth.admin.inviteUserByEmail(email, { data: metadata })
      : await adminClient.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: metadata });

    if (created.error || !created.data.user) {
      return json({ error: created.error?.message ?? 'Unable to create user' }, 400);
    }

    const newUser = created.data.user;
    const profileUpdate = await adminClient.from('profiles').upsert({
      id: newUser.id, email, first_name: firstName, last_name: lastName, phone: phone || null,
      department: department || null, specialization: specialization || null,
    }, { onConflict: 'id' });
    if (profileUpdate.error) {
      await adminClient.auth.admin.deleteUser(newUser.id);
      return json({ error: `Profile creation failed: ${profileUpdate.error.message}` }, 500);
    }

    const roleUpdate = await adminClient.from('user_roles').delete().eq('user_id', newUser.id);
    if (roleUpdate.error) {
      await adminClient.auth.admin.deleteUser(newUser.id);
      return json({ error: `Role initialization failed: ${roleUpdate.error.message}` }, 500);
    }
    const roleInsert = await adminClient.from('user_roles').insert({ user_id: newUser.id, role });
    if (roleInsert.error) {
      await adminClient.auth.admin.deleteUser(newUser.id);
      return json({ error: `Role assignment failed: ${roleInsert.error.message}` }, 500);
    }

    await adminClient.rpc('record_system_audit', {
      _action: 'admin_create_user', _module: 'administration', _entity_type: 'user',
      _entity_id: newUser.id, _severity: 'info',
      _metadata: { email, role, onboarding, created_user_id: newUser.id },
    });

    return json({
      ok: true,
      user: { id: newUser.id, email: newUser.email, first_name: firstName, last_name: lastName, role },
      onboarding,
    });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
