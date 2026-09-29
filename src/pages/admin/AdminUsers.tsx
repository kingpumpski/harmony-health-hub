import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { UserPlus, ShieldCheck, Settings, CheckCircle2, MailPlus, Pencil, Save, X } from 'lucide-react';
import { toast } from '@/hooks/use-toast';
import { RecordList, type RecordColumn, StatusBadge } from '@/components/records/RecordList';

const availableRoles = [
  { value: 'admin', label: 'Admin' }, { value: 'it_admin', label: 'IT Admin' }, { value: 'practitioner', label: 'Doctor' }, { value: 'nurse', label: 'Nurse' },
  { value: 'specialist_nurse', label: 'Specialist Nurse' }, { value: 'midwife', label: 'Midwife' }, { value: 'lab_technician', label: 'Lab Technician' },
  { value: 'pharmacist', label: 'Pharmacist' }, { value: 'radiologist', label: 'Radiologist' }, { value: 'radiology_technician', label: 'Radiology Technician' }, { value: 'accountant', label: 'Accountant' }, { value: 'front_desk', label: 'Front Desk' },
  { value: 'canteen', label: 'Canteen' }, { value: 'patient', label: 'Patient' },
] as const;
type RoleValue = string;
interface DirectoryRow { id: string; email: string | null; first_name: string | null; last_name: string | null; phone: string | null; department: string | null; specialization: string | null; role: string }
type EditableUser = Omit<DirectoryRow, 'role'>;

export default function AdminUsers() {
  const { user } = useAuth(); const canManage = user?.role === 'admin';
  const [users, setUsers] = useState<DirectoryRow[]>([]); const [searchEmail, setSearchEmail] = useState('');
  const [newRole, setNewRole] = useState<RoleValue>('practitioner'); const [loading, setLoading] = useState(false);
  const [createEmail, setCreateEmail] = useState(''); const [createFirstName, setCreateFirstName] = useState(''); const [createLastName, setCreateLastName] = useState('');
  const [createPhone, setCreatePhone] = useState(''); const [createDepartment, setCreateDepartment] = useState(''); const [createSpecialization, setCreateSpecialization] = useState('');
  const [createRole, setCreateRole] = useState<RoleValue>('patient'); const [onboarding, setOnboarding] = useState<'invite' | 'password'>('invite'); const [createPassword, setCreatePassword] = useState(''); const [creating, setCreating] = useState(false); const [editingUser, setEditingUser] = useState<EditableUser | null>(null); const [savingUser, setSavingUser] = useState(false);
  const getFunctionError = async (error: unknown, data: unknown, fallback: string) => {
    if (data && typeof data === 'object' && data !== null && 'error' in data) {
      const message = (data as { error?: unknown }).error;
      if (typeof message === 'string' && message.trim()) return message;
    }
    const context = (error as { context?: Response } | null)?.context;
    if (context) {
      try {
        const body = await context.clone().json() as { error?: unknown; message?: unknown };
        if (typeof body?.error === 'string' && body.error.trim()) return body.error;
        if (typeof body?.message === 'string' && body.message.trim()) return body.message;
      } catch {
        // The response may not contain JSON; keep the generic SDK message.
      }
    }
    return fallback;
  };
  const loadDirectory = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.functions.invoke('admin-create-user', { body: { action: 'list_users' } });
    if (error || data?.error) {
      setLoading(false);
      toast({ title: 'Directory unavailable', description: await getFunctionError(error, data, 'Unable to load user directory'), variant: 'destructive' });
      return;
    }
    setUsers(Array.isArray(data?.users) ? data.users : []);
    setLoading(false);
  }, []);
  useEffect(() => { if (canManage) void loadDirectory(); }, [canManage, loadDirectory]);
  const createUser = async (e: React.FormEvent) => {
    e.preventDefault(); setCreating(true);
    const { data, error } = await supabase.functions.invoke('admin-create-user', { body: { email: createEmail, firstName: createFirstName, lastName: createLastName, phone: createPhone, department: createDepartment, specialization: createSpecialization, role: createRole, onboarding, ...(onboarding === 'password' ? { password: createPassword } : {}) } });
    setCreating(false);
    if (error || data?.error) return toast({ title: 'User creation failed', description: await getFunctionError(error, data, 'Unable to create user'), variant: 'destructive' });
    toast({ title: onboarding === 'invite' ? 'Invitation sent' : 'User created', description: createFirstName + ' ' + createLastName + ' was added as ' + createRole + '.' });
    setCreateEmail(''); setCreateFirstName(''); setCreateLastName(''); setCreatePhone(''); setCreateDepartment(''); setCreateSpecialization(''); setCreatePassword(''); setCreateRole('patient'); setOnboarding('invite');
    void loadDirectory();
  };
  const saveUserProfile = async (e: React.FormEvent) => {
    e.preventDefault(); if (!editingUser) return; setSavingUser(true);
    const { data, error } = await supabase.functions.invoke('admin-create-user', { body: { action: 'update_profile', userId: editingUser.id, email: editingUser.email ?? '', firstName: editingUser.first_name ?? '', lastName: editingUser.last_name ?? '', phone: editingUser.phone ?? '', department: editingUser.department ?? '', specialization: editingUser.specialization ?? '' } });
    setSavingUser(false);
    if (error || data?.error) return toast({ title: 'Profile correction failed', description: await getFunctionError(error, data, 'Unable to save account information'), variant: 'destructive' });
    setEditingUser(null); toast({ title: 'Account information corrected', description: 'The updated user information has been saved and audited.' }); void loadDirectory();
  };
  const assignRole = async (userId: string, role: RoleValue) => {
    const { data, error } = await supabase.functions.invoke('admin-create-user', {
      body: { action: 'update_role', userId, role },
    });
    if (error || data?.error) return toast({ title: 'Role update failed', description: await getFunctionError(error, data, 'Unable to update role'), variant: 'destructive' });
    setUsers(current => current.map(row => row.id === userId ? { ...row, role } : row));
    toast({ title: 'Role updated', description: 'Set to ' + role });
    void loadDirectory();
  };
  const promoteByEmail = async (e: React.FormEvent) => {
    e.preventDefault(); if (!searchEmail.trim()) return;
    const { data: profile } = await supabase.from('profiles').select('id').eq('email', searchEmail.trim()).maybeSingle();
    if (!profile) return toast({ title: 'User not found', description: 'Ask the user to sign up first, then assign the role.', variant: 'destructive' });
    await assignRole(profile.id, newRole); setSearchEmail('');
  };
  const directoryColumns: RecordColumn<DirectoryRow>[] = [
    {
      key: 'name',
      header: 'User',
      render: (row) => <div className="min-w-0"><p className="font-medium truncate">{row.first_name || row.last_name ? (row.first_name ?? '') + ' ' + (row.last_name ?? '') : 'Unnamed'}</p><p className="text-xs text-muted-foreground truncate">{row.email ?? 'No email'}</p></div>,
    },
    {
      key: 'department',
      header: 'Department',
      hideBelow: 'md',
      render: (row) => <div><p className="text-sm">{row.department || 'No department'}</p><p className="text-xs text-muted-foreground">{row.specialization || 'No specialization'}</p></div>,
    },
    {
      key: 'role',
      header: 'Role',
      render: (row) => <StatusBadge status={availableRoles.find((role) => role.value === row.role)?.label ?? row.role} />,
    },
    {
      key: 'actions',
      header: 'Actions',
      align: 'right',
      render: (row) => <div className="flex justify-end gap-2" onClick={(event) => event.stopPropagation()}>
        <button type="button" onClick={() => setEditingUser({ id: row.id, email: row.email, first_name: row.first_name, last_name: row.last_name, phone: row.phone, department: row.department, specialization: row.specialization })} className="btn-secondary inline-flex items-center gap-1 text-xs"><Pencil className="w-3 h-3" />Edit</button>
        <select aria-label={`Change role for ${row.first_name || row.last_name || row.email || 'user'}`} value={row.role} onChange={e => void assignRole(row.id, e.target.value)} className="rounded-full bg-primary/10 px-3 py-1 text-xs font-semibold text-primary border-none">
          {availableRoles.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
        </select>
      </div>,
    },
  ];
  if (!user) return null;
  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h1 className="text-2xl font-heading font-bold">Admin User Management</h1><p className="text-muted-foreground">Multiple onboarding paths: create users directly, send invitations, or let users self-register and assign their role.</p></div><div className="inline-flex items-center gap-2 rounded-2xl border border-border bg-background p-3"><ShieldCheck className="w-5 h-5 text-success" /><span className="text-sm text-muted-foreground">Privileged access remains RLS-controlled.</span></div></div>
    {!canManage && <div className="rounded-2xl border border-warning/20 bg-warning/10 p-4 text-sm text-warning">You must be an admin to manage users.</div>}
    {canManage && <div className="grid gap-6 xl:grid-cols-[1fr_420px]">
      <div className="min-w-0">
        <RecordList
          title="Staff & Patient Directory"
          description="Assign or change the application role for existing accounts."
          data={users}
          columns={directoryColumns}
          isLoading={loading}
          rowKey={(row) => row.id}
          onRefresh={() => void loadDirectory()}
          isRefreshing={loading}
          emptyState={{ title: 'No users yet.', description: 'No staff or patient accounts are available in the administrative directory.' }}
        />
        {editingUser && <form onSubmit={saveUserProfile} className="card-medical mt-4 grid gap-2 border-t border-border p-5 md:grid-cols-2" aria-label="Edit user account">
          <div className="md:col-span-2 flex items-center justify-between gap-3"><div><h2 className="font-semibold">Edit account information</h2><p className="text-xs text-muted-foreground">Changes are saved through the existing server-authorized account workflow.</p></div><button type="button" disabled={savingUser} onClick={() => setEditingUser(null)} className="btn-secondary inline-flex items-center gap-1 text-xs"><X className="w-3 h-3" />Cancel</button></div>
          <input value={editingUser.first_name ?? ''} onChange={e=>setEditingUser({...editingUser,first_name:e.target.value})} className="input-medical" placeholder="First name" required/>
          <input value={editingUser.last_name ?? ''} onChange={e=>setEditingUser({...editingUser,last_name:e.target.value})} className="input-medical" placeholder="Last name" required/>
          <input type="email" value={editingUser.email ?? ''} onChange={e=>setEditingUser({...editingUser,email:e.target.value})} className="input-medical md:col-span-2" placeholder="Email address" required/>
          <input value={editingUser.phone ?? ''} onChange={e=>setEditingUser({...editingUser,phone:e.target.value})} className="input-medical" placeholder="Phone"/>
          <input value={editingUser.department ?? ''} onChange={e=>setEditingUser({...editingUser,department:e.target.value})} className="input-medical" placeholder="Department"/>
          <input value={editingUser.specialization ?? ''} onChange={e=>setEditingUser({...editingUser,specialization:e.target.value})} className="input-medical md:col-span-2" placeholder="Specialization"/>
          <div className="flex gap-2 md:col-span-2"><button type="submit" disabled={savingUser} className="btn-primary inline-flex items-center gap-2"><Save className="w-4 h-4"/>{savingUser?'Saving…':'Save corrections'}</button></div>
        </form>}
      </div>
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
          </form>
        </div>
        <div className="card-medical p-6"><div className="flex items-center justify-between mb-4"><div><h2 className="text-lg font-semibold">Promote Existing Account</h2><p className="text-sm text-muted-foreground">Self-registered users can still be assigned a facility role here.</p></div><Settings className="w-5 h-5 text-warning" /></div><form onSubmit={promoteByEmail} className="space-y-4"><input type="email" value={searchEmail} onChange={e => setSearchEmail(e.target.value)} className="input-medical w-full" placeholder="user@example.com" required /><select value={newRole} onChange={e => setNewRole(e.target.value)} className="input-medical w-full">{availableRoles.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}</select><button type="submit" className="btn-secondary w-full">Assign Role</button></form></div>
      </div>
    </div>}
    <div className="rounded-3xl border border-border bg-background/60 p-5"><div className="flex items-center gap-3 text-sm text-muted-foreground"><CheckCircle2 className="w-4 h-4" /><span>Onboarding is server-authorized: only administrators can invoke direct user creation, and role assignment is recorded through the existing audit boundary.</span></div></div>
  </div>;
}
