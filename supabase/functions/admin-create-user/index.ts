import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';
import { ADMIN_USER_ROLE_SET, provisionAdminUser, requireAdmin } from '../_shared/admin-user-provisioning.ts';

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  const cors = buildCorsHeaders(req);
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { ...cors, 'Content-Type': 'application/json' },
  });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Authentication required' }, 401);

    const service = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    const token = authHeader.replace(/^Bearer\s+/i, '');
    const caller = await requireAdmin(service, token);
    const body = await req.json();

    if (body?.action === 'update_role') {
      const userId = String(body?.userId ?? '').trim();
      const nextRole = String(body?.role ?? '').trim().toLowerCase();
      if (!userId || !ADMIN_USER_ROLE_SET.has(nextRole)) {
        return json({ error: 'A valid userId and supported role are required' }, 400);
      }
      if (userId === caller.id && nextRole !== 'admin') {
        return json({ error: 'Administrators cannot remove their own admin role' }, 400);
      }

      const { data: target, error: targetError } = await service.auth.admin.getUserById(userId);\n      if (targetError || !target.user) return json({ error: 'Target user not found' }, 404);\n\n      const roleDelete = await service.from('user_roles').delete().eq('user_id', userId);\n      if (roleDelete.error) return json({ error: 'Role update failed: ' + roleDelete.error.message }, 500);\n      const roleInsert = await service.from('user_roles').insert({ user_id: userId, role: nextRole });\n      if (roleInsert.error) return json({ error: 'Role update failed: ' + roleInsert.error.message }, 500);\n\n      await service.rpc('record_system_audit', {\n        _action: 'admin_update_user_role', _module: 'administration', _entity_type: 'user',\n        _entity_id: userId, _severity: 'info',\n        _metadata: { target_user_id: userId, role: nextRole, changed_by: caller.id },\n      });\n      return json({ ok: true, user: { id: userId, role: nextRole } });
    }

    const onboarding = body?.onboarding === 'password' ? 'password' : 'invite';
    const user = await provisionAdminUser(service, {
      email: String(body?.email ?? ''),
      firstName: String(body?.firstName ?? ''),
      lastName: String(body?.lastName ?? ''),
      phone: String(body?.phone ?? ''),
      department: String(body?.department ?? ''),
      specialization: String(body?.specialization ?? ''),
      role: String(body?.role ?? 'patient'),
      onboarding,
      password: onboarding === 'password' ? String(body?.password ?? '') : undefined,
    });

    await service.rpc('record_system_audit', {
      _action: 'admin_create_user', _module: 'administration', _entity_type: 'user',
      _entity_id: user.id, _severity: 'info',
      _metadata: { email: user.email, role: user.role, onboarding, created_user_id: user.id },
    });

    return json({ ok: true, user, onboarding });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = message === 'Invalid authentication' ? 401 : message === 'Administrator access required' ? 403 : 400;
    return json({ error: message }, status);
  }
});
