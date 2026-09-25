import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

export const ADMIN_USER_ROLES = [
  'admin','it_admin','practitioner','nurse','specialist_nurse','midwife','lab_technician',
  'pharmacist','accountant','front_desk','canteen','radiologist','radiology_technician','patient',
] as const;

export const ADMIN_USER_ROLE_SET = new Set<string>(ADMIN_USER_ROLES);

export interface AdminUserInput {
  email: string;
  firstName: string;
  lastName: string;
  phone?: string;
  department?: string;
  specialization?: string;
  role: string;
  onboarding: 'invite' | 'password';
  password?: string;
}

export async function requireAdmin(service: SupabaseClient, token: string) {
  const { data: { user: caller }, error: callerError } = await service.auth.getUser(token);
  if (callerError || !caller) throw new Error('Invalid authentication');

  const { data: callerRole, error: roleError } = await service
    .from('user_roles')
    .select('role')
    .eq('user_id', caller.id)
    .eq('role', 'admin')
    .maybeSingle();
  if (roleError) throw new Error('Unable to verify administrator access');
  if (!callerRole) throw new Error('Administrator access required');

  return caller;
}

export async function provisionAdminUser(service: SupabaseClient, input: AdminUserInput) {
  const email = input.email.trim().toLowerCase();
  const firstName = input.firstName.trim();
  const lastName = input.lastName.trim();
  const phone = (input.phone ?? '').trim();
  const department = (input.department ?? '').trim();
  const specialization = (input.specialization ?? '').trim();
  const role = input.role.trim().toLowerCase();

  if (!email.includes('@') || !firstName || !lastName) {
    throw new Error('email, first_name and last_name are required');
  }
  if (!ADMIN_USER_ROLE_SET.has(role)) throw new Error('Unsupported role');
  if (input.onboarding === 'password' && (input.password ?? '').length < 8) {
    throw new Error('Password onboarding requires at least 8 characters');
  }

  const metadata = { first_name: firstName, last_name: lastName, phone, department, specialization };
  const created = input.onboarding === 'password'
    ? await service.auth.admin.createUser({
        email, password: input.password!, email_confirm: true, user_metadata: metadata,
      })
    : await service.auth.admin.inviteUserByEmail(email, { data: metadata });

  if (created.error || !created.data.user) {
    throw new Error(created.error?.message ?? 'Unable to create authenticated user');
  }

  const newUser = created.data.user;
  let provisioned = false;
  try {
    const profile = await service.from('profiles').upsert({
      id: newUser.id, email, first_name: firstName, last_name: lastName,
      phone: phone || null, department: department || null, specialization: specialization || null,
    }, { onConflict: 'id' });
    if (profile.error) throw new Error('Profile creation failed: ' + profile.error.message);

    const roleDelete = await service.from('user_roles').delete().eq('user_id', newUser.id);
    if (roleDelete.error) throw new Error('Role initialization failed: ' + roleDelete.error.message);

    const roleInsert = await service.from('user_roles').insert({ user_id: newUser.id, role });
    if (roleInsert.error) throw new Error('Role assignment failed: ' + roleInsert.error.message);

    provisioned = true;
    return { id: newUser.id, email: newUser.email, first_name: firstName, last_name: lastName, role };
  } finally {
    if (!provisioned) await service.auth.admin.deleteUser(newUser.id);
  }
}
