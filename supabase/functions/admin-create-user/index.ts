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

    if (body?.action === 'list_users') {
      const { data: profiles, error: profileError } = await service
        .from('profiles')
        .select('id, email, first_name, last_name, created_at')
        .order('created_at', { ascending: false })
        .limit(200);
      if (profileError) return json({ error: 'User directory lookup failed: ' + profileError.message }, 500);
      const ids = (profiles ?? []).map((p) => p.id);
      const { data: roles, error: roleError } = ids.length
        ? await service.from('user_roles').select('user_id, role').in('user_id', ids)
        : { data: [], error: null };
      if (roleError) return json({ error: 'Role directory lookup failed: ' + roleError.message }, 500);
      const roleMap = new Map<string, string>();
      (roles ?? []).forEach((row) => roleMap.set(row.user_id, String(row.role)));
      return json({
        ok: true,
        users: (profiles ?? []).map((profile) => ({
          id: profile.id,
          email: profile.email,
          first_name: profile.first_name,
          last_name: profile.last_name,
          role: roleMap.get(profile.id) ?? 'patient',
        })),
      });
    }

    if (body?.action === 'update_role') {
      const userId = String(body?.userId ?? '').trim();
      const nextRole = String(body?.role ?? '').trim().toLowerCase();
      if (!userId || !ADMIN_USER_ROLE_SET.has(nextRole)) {
        return json({ error: 'A valid userId and supported role are required' }, 400);
      }
      if (userId === caller.id && nextRole !== 'admin') {
        return json({ error: 'Administrators cannot remove their own admin role' }, 400);
      }

      const { data: target, error: targetError } = await service.auth.admin.getUserById(userId);
      if (targetError || !target.user) return json({ error: 'Target user not found' }, 404);

      const { data: previousRows, error: previousRoleError } = await service
        .from('user_roles')
        .select('role, created_at')
        .eq('user_id', userId)
        .order('created_at', { ascending: true });
      if (previousRoleError) return json({ error: 'Unable to read current role: ' + previousRoleError.message }, 500);
      const previousRole = previousRows?.[0]?.role ? String(previousRows[0].role) : null;

      const roleDelete = await service.from('user_roles').delete().eq('user_id', userId);
      if (roleDelete.error) return json({ error: 'Role update failed: ' + roleDelete.error.message }, 500);

      const roleInsert = await service.from('user_roles').insert({ user_id: userId, role: nextRole });
      if (roleInsert.error) {
        if (previousRole) await service.from('user_roles').insert({ user_id: userId, role: previousRole });
        return json({ error: 'Role update failed: ' + roleInsert.error.message }, 500);
      }

      const { error: auditError } = await service.rpc('record_system_audit', {
        _action: 'admin_update_user_role', _module: 'administration', _entity_type: 'user',
        _entity_id: userId, _severity: 'info',
        _metadata: { target_user_id: userId, role: nextRole, previous_role: previousRole, changed_by: caller.id },
      });
      if (auditError) {
        await service.from('user_roles').delete().eq('user_id', userId);
        if (previousRole) await service.from('user_roles').insert({ user_id: userId, role: previousRole });
        return json({ error: 'Role update was rolled back because audit recording failed' }, 500);
      }
      return json({ ok: true, user: { id: userId, role: nextRole } });
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
      password: String(body?.password ?? ''),
    });

    const { error: auditError } = await service.rpc('record_system_audit', {
      _action: 'admin_create_user', _module: 'administration', _entity_type: 'user',
      _entity_id: user.id, _severity: 'info',
      _metadata: { email: user.email, role: user.role, onboarding, created_user_id: user.id },
    });
    if (auditError) return json({ error: 'User created but audit recording failed' }, 500);

    return json({ ok: true, user, onboarding });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
