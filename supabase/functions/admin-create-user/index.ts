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
    const { data: callerRoleRow } = await service.from('user_roles').select('role').eq('user_id', caller.id).in('role', ['admin','system_superuser']).limit(1).maybeSingle();
    const callerRole = String(callerRoleRow?.role ?? '');
    const body = await req.json();

    // This function is called with the service-role client, so auth.uid() is NULL.
    // record_system_audit() intentionally rejects that context. Write the audit
    // row directly with the already-authorized service client while preserving the
    // real administrator as actor_id.
    const writeAdminAudit = async (input: {
      action: string;
      entityId: string;
      metadata: Record<string, unknown>;
    }) => {
      const { error } = await service.from('system_audit_log').insert({
        actor_id: caller.id,
        action: input.action,
        module: 'administration',
        entity_type: 'user',
        entity_id: input.entityId,
        severity: 'info',
        metadata: input.metadata,
      });
      if (error) throw new Error('Audit recording failed: ' + error.message);
    };

    if (body?.action === 'list_users') {
      const { data: profiles, error: profileError } = await service
        .from('profiles')
        .select('id, email, first_name, last_name, phone, department, specialization, created_at')
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
          phone: profile.phone,
          department: profile.department,
          specialization: profile.specialization,
          role: roleMap.get(profile.id) ?? 'patient',
        })),
      });
    }

    if (body?.action === 'update_profile') {
      const userId = String(body?.userId ?? '').trim();
      const email = String(body?.email ?? '').trim().toLowerCase();
      const firstName = String(body?.firstName ?? '').trim();
      const lastName = String(body?.lastName ?? '').trim();
      const phone = String(body?.phone ?? '').trim();
      const department = String(body?.department ?? '').trim();
      const specialization = String(body?.specialization ?? '').trim();
      if (!userId || !email.includes('@') || !firstName || !lastName) return json({ error: 'userId, valid email, first name and last name are required' }, 400);
      const { data: target, error: targetError } = await service.auth.admin.getUserById(userId);
      if (targetError || !target.user) return json({ error: 'Target user not found' }, 404);
      const { data: previousProfile, error: previousProfileError } = await service.from('profiles').select('email, first_name, last_name, phone, department, specialization').eq('id', userId).maybeSingle();
      if (previousProfileError) return json({ error: 'Unable to read current profile: ' + previousProfileError.message }, 500);
      const previousAuth = { email: target.user.email ?? '', user_metadata: target.user.user_metadata ?? {} };
      const nextMetadata = { ...previousAuth.user_metadata, first_name: firstName, last_name: lastName, phone, department, specialization };
      const authUpdate = await service.auth.admin.updateUserById(userId, { email, user_metadata: nextMetadata });
      if (authUpdate.error) return json({ error: 'Account identity update failed: ' + authUpdate.error.message }, 400);
      const profileUpdate = await service.from('profiles').update({ email, first_name: firstName, last_name: lastName, phone: phone || null, department: department || null, specialization: specialization || null, updated_at: new Date().toISOString() }).eq('id', userId);
      if (profileUpdate.error) {
        await service.auth.admin.updateUserById(userId, { email: previousAuth.email || undefined, user_metadata: previousAuth.user_metadata });
        return json({ error: 'Profile update failed: ' + profileUpdate.error.message }, 500);
      }
      try {
        await writeAdminAudit({ action: 'admin_update_user_profile', entityId: userId, metadata: { target_user_id: userId, previous_profile: previousProfile, next_profile: { email, first_name: firstName, last_name: lastName, phone, department, specialization }, changed_by: caller.id } });
      } catch (auditError) {
        await service.from('profiles').update({ email: previousProfile?.email ?? null, first_name: previousProfile?.first_name ?? null, last_name: previousProfile?.last_name ?? null, phone: previousProfile?.phone ?? null, department: previousProfile?.department ?? null, specialization: previousProfile?.specialization ?? null, updated_at: new Date().toISOString() }).eq('id', userId);
        await service.auth.admin.updateUserById(userId, { email: previousAuth.email || undefined, user_metadata: previousAuth.user_metadata });
        throw auditError;
      }
      return json({ ok: true, user: { id: userId, email, first_name: firstName, last_name: lastName, phone: phone || null, department: department || null, specialization: specialization || null } });
    }

    if (body?.action === 'update_role') {
      const userId = String(body?.userId ?? '').trim();
      const nextRole = String(body?.role ?? '').trim().toLowerCase();
      if (!userId || !ADMIN_USER_ROLE_SET.has(nextRole)) {
        return json({ error: 'A valid userId and supported role are required' }, 400);
      }
      if (userId === caller.id && nextRole !== callerRole) {
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

      try {
        await writeAdminAudit({
          action: 'admin_update_user_role',
          entityId: userId,
          metadata: { target_user_id: userId, role: nextRole, previous_role: previousRole, changed_by: caller.id },
        });
      } catch (auditError) {
        await service.from('user_roles').delete().eq('user_id', userId);
        if (previousRole) await service.from('user_roles').insert({ user_id: userId, role: previousRole });
        throw auditError;
      }

      return json({ ok: true, user: { id: userId, role: nextRole } });
    }

    if (String(body?.role ?? '').trim().toLowerCase() === 'system_superuser' && callerRole !== 'system_superuser') return json({ error: 'Only a System Superuser can create or assign another System Superuser.' }, 403);

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

    try {
      await writeAdminAudit({
        action: 'admin_create_user',
        entityId: user.id,
        metadata: { email: user.email, role: user.role, onboarding, created_user_id: user.id },
      });
    } catch (auditError) {
      // Do not leave an account behind after a failed completion step.
      await service.auth.admin.deleteUser(user.id);
      throw auditError;
    }

    return json({ ok: true, user, onboarding });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
