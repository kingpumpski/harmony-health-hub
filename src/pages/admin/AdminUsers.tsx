import { useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { UserPlus, ShieldCheck, Settings, CheckCircle2, MailPlus } from 'lucide-react';
import { toast } from '@/hooks/use-toast';

const availableRoles = [
  { value: 'admin', label: 'Admin' }, { value: 'practitioner', label: 'Doctor' }, { value: 'nurse', label: 'Nurse' },
  { value: 'specialist_nurse', label: 'Specialist Nurse' }, { value: 'midwife', label: 'Midwife' }, { value: 'lab_technician', label: 'Lab Technician' },
  { value: 'pharmacist', label: 'Pharmacist' }, { value: 'radiologist', label: 'Radiologist' }, { value: 'accountant', label: 'Accountant' }, { value: 'front_desk', label: 'Front Desk' },
  { value: 'canteen', label: 'Canteen' }, { value: 'patient', label: 'Patient' },
] as const;
type RoleValue = string;
interface DirectoryRow { id: string; email: string | null; first_name: string | null; last_name: string | null; role: string }

export default function AdminUsers() {
  const { user } = useAuth(); const canManage = user?.role === 'admin';
  const [users, setUsers] = useState<DirectoryRow[]>([]); const [searchEmail, setSearchEmail] = useState('');
  const [newRole, setNewRole] = useState<RoleValue>('practitioner'); const [loading, setLoading] = useState(false);
  const [createEmail, setCreateEmail] = useState(''); const [createFirstName, setCreateFirstName] = useState(''); const [createLastName, setCreateLastName] = useState('');
  const [createPhone, setCreatePhone] = useState(''); const [createDepartment, setCreateDepartment] = useState(''); const [createSpecialization, setCreateSpecialization] = useState('');
  const [createRole, setCreateRole] = useState<RoleValue>('patient'); const [onboarding, setOnboarding] = useState<'invite' | 'password'>('invite'); const [createPassword, setCreatePassword] = useState(''); const [creating, setCreating] = useState(false);
  const loadDirectory = async () => {
    setLoading(true);
    const { data: profiles } = await supabase.from('profiles').select('id, email, first_name, last_name').order('created_at', { ascending: false }).limit(200);
    const ids = (profiles ?? []).map(p => p.id);
    const { data: roles } = await supabase.from('user_roles').select('user_id, role').in('user_id', ids.length ? ids : ['00000000-0000-0000-0000-000000000000']);
    const roleMap = new Map<string, string>(); (roles ?? []).forEach(r => roleMap.set(r.user_id, String(r.role)));
    setUsers((profiles ?? []).map(p => ({ id: p.id, email: p.email, first_name: p.first_name, last_name: p.last_name, role: roleMap.get(p.id) ?? 'patient' }))); setLoading(false);
  };
  useEffect(() => { if (canManage) void loadDirectory(); }, [canManage]);
  const createUser = async (e: React.FormEvent) => {
    e.preventDefault(); setCreating(true);
    const { data, error } = await supabase.functions.invoke('admin-create-user', { body: { email: createEmail, firstName: createFirstName, lastName: createLastName, phone: createPhone, department: createDepartment, specialization: createSpecialization, role: createRole, onboarding, ...(onboarding === 'password' ? { password: createPassword } : {}) } });
    setCreating(false);
    if (error || data?.error) return toast({ title: 'User creation failed', description: data?.error ?? error?.message ?? 'Unable to create user', variant: 'destructive' });
    toast({ title: onboarding === 'invite' ? 'Invitation sent' : 'User created', description: createFirstName + ' ' + createLastName + ' was added as ' + createRole + '.' });
    setCreateEmail(''); setCreateFirstName(''); setCreateLastName(''); setCreatePhone(''); setCreateDepartment(''); setCreateSpecialization(''); setCreatePassword(''); setCreateRole('patient'); setOnboarding('invite');
    void loadDirectory();
  };
  const assignRole = async (userId: string, role: RoleValue) => {
    const { error: delErr } = await supabase.from('user_roles').delete().eq('user_id', userId); if (delErr) return toast({ title: 'Failed', description: delErr.message, variant: 'destructive' });
    const { error } = await supabase.from('user_roles').insert({ user_id: userId, role } as never); if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Role updated', description: 'Set to ' + role }); void loadDirectory();
  };
  const promoteByEmail = async (e: React.FormEvent) => {
    e.preventDefault(); if (!searchEmail.trim()) return;
    const { data: profile } = await supabase.from('profiles').select('id').eq('email', searchEmail.trim()).maybeSingle();
    if (!profile) return toast({ title: 'User not found', description: 'Ask the user to sign up first, then assign the role.', variant: 'destructive' });
    await assignRole(profile.id, newRole); setSearchEmail('');
  };
  if (!user) return null;
  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h1 className="text-2xl font-heading font-bold">Admin User Management</h1><p className="text-muted-foreground">Multiple onboarding paths: create users directly, send invitations, or let users self-register and assign their role.</p></div><div className="inline-flex items-center gap-2 rounded-2xl border border-border bg-background p-3"><ShieldCheck className="w-5 h-5 text-success" /><span className="text-sm text-muted-foreground">Privileged access remains RLS-controlled.</span></div></div>
    {!canManage && <div className="rounded-2xl border border-warning/20 bg-warning/10 p-4 text-sm text-warning">You must be an admin to manage users.</div>}
    {canManage && <div className="grid gap-6 xl:grid-cols-[1fr_420px]">
      <div className="card-medical p-6"><div className="flex items-center justify-between mb-4"><div><h2 className="text-lg font-semibold">Staff & Patient Directory</h2><p className="text-sm text-muted-foreground">Assign or change the application role for existing accounts.</p></div><UserPlus className="w-5 h-5 text-primary" /></div><div className="space-y-3">{loading && <p className="text-sm text-muted-foreground">Loading…</p>}{users.map(u => <div key={u.id} className="rounded-2xl border border-border p-4 flex items-center justify-between gap-3"><div><p className="font-medium">{u.first_name || u.last_name ? (u.first_name ?? '') + ' ' + (u.last_name ?? '') : 'Unnamed'}</p><p className="text-xs text-muted-foreground">{u.email}</p></div><select value={u.role} onChange={e => void assignRole(u.id, e.target.value)} className="rounded-full bg-primary/10 px-3 py-1 text-xs font-semibold text-primary border-none">{availableRoles.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}</select></div>)}{!loading && users.length === 0 && <p className="text-sm text-muted-foreground">No users yet.</p>}</div></div>
      <div className="space-y-6">
        <div className="card-medical p-6"><div className="flex items-center justify-between mb-4"><div><h2 className="text-lg font-semibold">Create / Invite User</h2><p className="text-sm text-muted-foreground">Admin-created onboarding. Invitation sends the user their account setup email.</p></div><MailPlus className="w-5 h-5 text-primary" /></div>
          <form onSubmit={createUser} className="space-y-3">
            <div className="grid grid-cols-2 gap-2"><input value={createFirstName} onChange={e => setCreateFirstName(e.target.value)} className="input-medical" placeholder="First name" required /><input value={createLastName} onChange={e => setCreateLastName(e.target.value)} className="input-medical" placeholder="Last name" required /></div>
            <input type="email" value={createEmail} onChange={e => setCreateEmail(e.target.value)} className="input-medical w-full" placeholder="Email address" required />
            <input value={createPhone} onChange={e => setCreatePhone(e.target.value)} className="input-medical w-full" placeholder="Phone (optional)" />
            <div className="grid grid-cols-2 gap-2"><input value={createDepartment} onChange={e => setCreateDepartment(e.target.value)} className="input-medical" placeholder="Department" /><input value={createSpecialization} onChange={e => setCreateSpecialization(e.target.value)} className="input-medical" placeholder="Specialization" /></div>
            <select value={createRole} onChange={e => setCreateRole(e.target.value)} className="input-medical w-full">{availableRoles.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}</select>
            <select value={onboarding} onChange={e => setOnboarding(e.target.value as 'invite' | 'password')} className="input-medical w-full"><option value="invite">Email invitation</option><option value="password">Create with password</option></select>
            {onboarding === 'password' && <input type="password" minLength={8} value={createPassword} onChange={e => setCreatePassword(e.target.value)} className="input-medical w-full" placeholder="Initial password (8+ characters)" required />}
            <button type="submit" disabled={creating} className="btn-primary w-full"><UserPlus className="w-4 h-4" />{creating ? 'Creating…' : onboarding === 'invite' ? 'Create & Send Invitation' : 'Create User'}</button>
          </form></div>
        <div className="card-medical p-6"><div className="flex items-center justify-between mb-4"><div><h2 className="text-lg font-semibold">Promote Existing Account</h2><p className="text-sm text-muted-foreground">Self-registered users can still be assigned a facility role here.</p></div><Settings className="w-5 h-5 text-warning" /></div><form onSubmit={promoteByEmail} className="space-y-4"><input type="email" value={searchEmail} onChange={e => setSearchEmail(e.target.value)} className="input-medical w-full" placeholder="user@example.com" required /><select value={newRole} onChange={e => setNewRole(e.target.value)} className="input-medical w-full">{availableRoles.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}</select><button type="submit" className="btn-secondary w-full">Assign Role</button></form></div>
      </div>
    </div>}
    <div className="rounded-3xl border border-border bg-background/60 p-5"><div className="flex items-center gap-3 text-sm text-muted-foreground"><CheckCircle2 className="w-4 h-4" /><span>Onboarding is server-authorized: only administrators can invoke direct user creation, and role assignment is recorded through the existing audit boundary.</span></div></div>
  </div>;
}