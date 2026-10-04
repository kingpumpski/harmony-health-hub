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
    const { data: callerRoleRow } = await service.from('user_roles').select('role').eq('user_id', caller.id).in('role', ['admin','it_admin','system_superuser']).limit(1).maybeSingle();
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
      let visibleUserIds: string[] | null = null;
      if (callerRole !== 'system_superuser') {
        const { data: callerContext, error: callerContextError } = await service
          .from('user_active_facilities')
          .select('facility_id')
          .eq('user_id', caller.id)
          .maybeSingle();
        if (callerContextError) return json({ error: 'Unable to determine administrator facility context: ' + callerContextError.message }, 500);
        if (!callerContext?.facility_id) return json({ error: 'An active facility context is required before viewing facility users.' }, 400);
        const { data: memberships, error: membershipScopeError } = await service
          .from('facility_memberships')
          .select('user_id')
          .eq('facility_id', callerContext.facility_id)
          .eq('is_active', true);
        if (membershipScopeError) return json({ error: 'Facility user directory lookup failed: ' + membershipScopeError.message }, 500);
        visibleUserIds = Array.from(new Set((memberships ?? []).map((row) => row.user_id)));
      }

      let profileQuery = service
        .from('profiles')
        .select('id, email, first_name, last_name, phone, department, specialization, created_at')
        .order('created_at', { ascending: false })
        .limit(200);
      if (visibleUserIds) {
        if (!visibleUserIds.length) return json({ ok: true, users: [] });
        profileQuery = profileQuery.in('id', visibleUserIds);
      }
      const { data: profiles, error: profileError } = await profileQuery;
      if (profileError) return json({ error: 'User directory lookup failed: ' + profileError.message }, 500);
      const ids = (profiles ?? []).map((p) => p.id);
      const { data: roles, error: roleError } = ids.length
        ? await service.from('user_roles').select('user_id, role').in('user_id', ids)
        : { data: [], error: null };
      if (roleError) return json({ error: 'Role directory lookup failed: ' + roleError.message }, 500);
      const { data: memberships, error: membershipError } = ids.length
        ? await service.from('facility_memberships').select('user_id, facility_id, access_scope, is_active, healthcare_facilities(name, facility_code)').in('user_id', ids)
        : { data: [], error: null };
      if (membershipError) return json({ error: 'Facility membership lookup failed: ' + membershipError.message }, 500);
      const { data: activeContexts, error: activeContextError } = ids.length
        ? await service.from('user_active_facilities').select('user_id, facility_id').in('user_id', ids)
        : { data: [], error: null };
      if (activeContextError) return json({ error: 'Active facility lookup failed: ' + activeContextError.message }, 500);
      const roleMap = new Map<string, string>();
      (roles ?? []).forEach((row) => roleMap.set(row.user_id, String(row.role)));
      const activeMap = new Map<string, string>();
      (activeContexts ?? []).forEach((row) => activeMap.set(row.user_id, row.facility_id));
      const membershipMap = new Map<string, Array<Record<string, unknown>>>();
      (memberships ?? []).forEach((row) => {
        const list = membershipMap.get(row.user_id) ?? [];
        const facility = Array.isArray(row.healthcare_facilities) ? row.healthcare_facilities[0] : row.healthcare_facilities;
        list.push({ facility_id: row.facility_id, facility_name: facility?.name ?? null, facility_code: facility?.facility_code ?? null, access_scope: row.access_scope, is_active: row.is_active, is_active_context: activeMap.get(row.user_id) === row.facility_id });
        membershipMap.set(row.user_id, list);
      });
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
          facilities: membershipMap.get(profile.id) ?? [],
        })),
      });
    }

    if (body?.action === 'set_facility_membership') {
      if (callerRole !== 'system_superuser') return json({ error: 'Only a System Superuser can manage cross-facility membership.' }, 403);
      const userId = String(body?.userId ?? '').trim();
      const facilityId = String(body?.facilityId ?? '').trim();
      const isActive = body?.isActive !== false;
      const accessScope = String(body?.accessScope ?? 'facility').trim().toLowerCase();
      if (!userId || !facilityId || !['facility','district','regional','national'].includes(accessScope)) return json({ error: 'userId, facilityId and a supported access scope are required' }, 400);
      const { data: target, error: targetError } = await service.auth.admin.getUserById(userId);
      if (targetError || !target.user) return json({ error: 'Target user not found' }, 404);
      const { data: facility, error: facilityError } = await service.from('healthcare_facilities').select('id,name,is_active').eq('id', facilityId).maybeSingle();
      if (facilityError) return json({ error: 'Facility lookup failed: ' + facilityError.message }, 500);
      if (!facility) return json({ error: 'Facility not found' }, 404);
      if (isActive && !facility.is_active) return json({ error: 'Cannot activate membership for an inactive facility' }, 400);
      const { data: membership, error: membershipError } = await service.from('facility_memberships').upsert({ user_id: userId, facility_id: facilityId, access_scope: accessScope, is_active: isActive }, { onConflict: 'facility_id,user_id' }).select('id, user_id, facility_id, access_scope, is_active').single();
      if (membershipError) return json({ error: 'Facility membership update failed: ' + membershipError.message }, 500);
      if (!isActive) {
        const { error: activeDeleteError } = await service.from('user_active_facilities').delete().eq('user_id', userId).eq('facility_id', facilityId);
        if (activeDeleteError) return json({ error: 'Active facility context cleanup failed: ' + activeDeleteError.message }, 500);
      }
      await writeAdminAudit({ action: 'platform_set_user_facility_membership', entityId: membership.id, metadata: { target_user_id: userId, facility_id: facilityId, is_active: isActive, access_scope: accessScope, changed_by: caller.id } });
      return json({ ok: true, membership });
    }

    if (body?.action === 'set_active_facility') {
      if (callerRole !== 'system_superuser') return json({ error: 'Only a System Superuser can set another user\'s active facility context.' }, 403);
      const userId = String(body?.userId ?? '').trim();
      const facilityId = String(body?.facilityId ?? '').trim();
      if (!userId || !facilityId) return json({ error: 'userId and facilityId are required' }, 400);
      const { data: membership } = await service.from('facility_memberships').select('facility_id').eq('user_id', userId).eq('facility_id', facilityId).eq('is_active', true).maybeSingle();
      if (!membership) return json({ error: 'User must have an active membership before a facility can be selected as active context' }, 400);
      const { data: facility } = await service.from('healthcare_facilities').select('id,name,is_active').eq('id', facilityId).maybeSingle();
      if (!facility?.is_active) return json({ error: 'Facility is not active' }, 400);
      const { error: activeError } = await service.from('user_active_facilities').upsert({ user_id: userId, facility_id: facilityId, updated_at: new Date().toISOString() }, { onConflict: 'user_id' });
      if (activeError) return json({ error: 'Active facility context update failed: ' + activeError.message }, 500);
      await writeAdminAudit({ action: 'platform_set_user_active_facility', entityId: userId, metadata: { target_user_id: userId, facility_id: facilityId, changed_by: caller.id } });
      return json({ ok: true, user_id: userId, facility_id: facilityId, facility_name: facility.name });
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
      if (callerRole !== 'system_superuser') {
        const { data: callerContext, error: callerContextError } = await service
          .from('user_active_facilities')
          .select('facility_id')
          .eq('user_id', caller.id)
          .maybeSingle();
        if (callerContextError) return json({ error: 'Unable to determine administrator facility context: ' + callerContextError.message }, 500);
        if (!callerContext?.facility_id) return json({ error: 'An active facility context is required before editing facility users.' }, 400);
        const { data: targetMembership } = await service
          .from('facility_memberships')
          .select('id')
          .eq('user_id', userId)
          .eq('facility_id', callerContext.facility_id)
          .eq('is_active', true)
          .maybeSingle();
        if (!targetMembership) return json({ error: 'Target user is not an active member of your facility.' }, 403);
      }
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
      if (callerRole !== 'system_superuser' && ['admin','it_admin','system_superuser'].includes(nextRole)) {
        return json({ error: 'Only a System Superuser can assign platform administrator roles.' }, 403);
      }

      const { data: target, error: targetError } = await service.auth.admin.getUserById(userId);
      if (targetError || !target.user) return json({ error: 'Target user not found' }, 404);

      if (callerRole !== 'system_superuser') {
        const { data: callerContext, error: callerContextError } = await service
          .from('user_active_facilities')
          .select('facility_id')
          .eq('user_id', caller.id)
          .maybeSingle();
        if (callerContextError) return json({ error: 'Unable to determine administrator facility context: ' + callerContextError.message }, 500);
        if (!callerContext?.facility_id) return json({ error: 'An active facility context is required before managing facility users.' }, 400);
        const { data: targetMembership } = await service
          .from('facility_memberships')
          .select('id')
          .eq('user_id', userId)
          .eq('facility_id', callerContext.facility_id)
          .eq('is_active', true)
          .maybeSingle();
        if (!targetMembership) return json({ error: 'Target user is not an active member of your facility.' }, 403);
      }

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

    const onboarding = body?.onboarding === 'password' ? 'password' : 'invite';
    const requestedRole = String(body?.role ?? 'patient').trim().toLowerCase();
    if (!ADMIN_USER_ROLE_SET.has(requestedRole)) return json({ error: 'Unsupported role' }, 400);
    if (requestedRole === 'system_superuser' && callerRole !== 'system_superuser') {
      return json({ error: 'Only a System Superuser can create or assign another System Superuser.' }, 403);
    }

    let requestedFacilityId = String(body?.facilityId ?? '').trim();
    if (callerRole === 'system_superuser') {
      if (requestedFacilityId) {
        const { data: facility } = await service.from('healthcare_facilities').select('id,is_active').eq('id', requestedFacilityId).maybeSingle();
        if (!facility) return json({ error: 'Requested facility not found' }, 400);
        if (!facility.is_active) return json({ error: 'Requested facility is inactive' }, 400);
      }
    } else {
      const { data: callerContext, error: callerContextError } = await service
        .from('user_active_facilities')
        .select('facility_id')
        .eq('user_id', caller.id)
        .maybeSingle();
      if (callerContextError) return json({ error: 'Unable to determine administrator facility context: ' + callerContextError.message }, 500);
      if (!callerContext?.facility_id) return json({ error: 'An active facility context is required before creating facility users.' }, 400);
      requestedFacilityId = String(callerContext.facility_id);
    }

    const user = await provisionAdminUser(service, {
      email: String(body?.email ?? ''),
      firstName: String(body?.firstName ?? ''),
      lastName: String(body?.lastName ?? ''),
      phone: String(body?.phone ?? ''),
      department: String(body?.department ?? ''),
      specialization: String(body?.specialization ?? ''),
      role: requestedRole,
      onboarding,
      password: String(body?.password ?? ''),
    });

    try {
      await writeAdminAudit({
        action: 'admin_create_user',
        entityId: user.id,
        metadata: { email: user.email, role: user.role, onboarding, created_user_id: user.id, facility_id: requestedFacilityId || null },
      });
    } catch (auditError) {
      await service.auth.admin.deleteUser(user.id);
      throw auditError;
    }

    if (requestedFacilityId) {
      const { data: facility } = await service.from('healthcare_facilities').select('id,is_active').eq('id', requestedFacilityId).maybeSingle();
      if (!facility) { await service.auth.admin.deleteUser(user.id); return json({ error: 'Requested facility not found' }, 400); }
      if (!facility.is_active) { await service.auth.admin.deleteUser(user.id); return json({ error: 'Requested facility is inactive' }, 400); }
      const { error: membershipError } = await service.from('facility_memberships').upsert({ user_id: user.id, facility_id: requestedFacilityId, access_scope: 'facility', is_active: true }, { onConflict: 'facility_id,user_id' });
      if (membershipError) { await service.auth.admin.deleteUser(user.id); return json({ error: 'Initial facility membership failed: ' + membershipError.message }, 500); }
      const { error: activeError } = await service.from('user_active_facilities').upsert({ user_id: user.id, facility_id: requestedFacilityId, updated_at: new Date().toISOString() }, { onConflict: 'user_id' });
      if (activeError) { await service.from('facility_memberships').update({ is_active: false }).eq('user_id', user.id).eq('facility_id', requestedFacilityId); await service.auth.admin.deleteUser(user.id); return json({ error: 'Initial facility context failed: ' + activeError.message }, 500); }
      try {
        await writeAdminAudit({ action: 'platform_onboard_user_facility', entityId: user.id, metadata: { target_user_id: user.id, facility_id: requestedFacilityId, role: user.role, changed_by: caller.id } });
      } catch (auditError) {
        await service.from('user_active_facilities').delete().eq('user_id', user.id).eq('facility_id', requestedFacilityId);
        await service.from('facility_memberships').delete().eq('user_id', user.id).eq('facility_id', requestedFacilityId);
        await service.auth.admin.deleteUser(user.id);
        throw auditError;
      }
    }
    return json({ ok: true, user, onboarding, facility_id: requestedFacilityId || null });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
