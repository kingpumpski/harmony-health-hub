import { useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { UserPlus, ShieldCheck, Settings, CheckCircle2 } from 'lucide-react';
import { toast } from '@/hooks/use-toast';

const availableRoles = [
  { value: 'admin', label: 'Admin' }, { value: 'practitioner', label: 'Doctor' }, { value: 'nurse', label: 'Nurse' },
  { value: 'specialist_nurse', label: 'Specialist Nurse' }, { value: 'midwife', label: 'Midwife' }, { value: 'lab_technician', label: 'Lab Technician' },
  { value: 'pharmacist', label: 'Pharmacist' }, { value: 'accountant', label: 'Accountant' }, { value: 'front_desk', label: 'Front Desk' },
  { value: 'canteen', label: 'Canteen' }, { value: 'patient', label: 'Patient' },
] as const;
type RoleValue = string;
interface DirectoryRow { id: string; email: string | null; first_name: string | null; last_name: string | null; role: string }

export default function AdminUsers() {
  const { user } = useAuth(); const canManage = user?.role === 'admin';
  const [users, setUsers] = useState<DirectoryRow[]>([]); const [searchEmail, setSearchEmail] = useState('');
  const [newRole, setNewRole] = useState<RoleValue>('practitioner'); const [loading, setLoading] = useState(false);
  const loadDirectory = async () => {
    setLoading(true);
    const { data: profiles } = await supabase.from('profiles').select('id, email, first_name, last_name').order('created_at', { ascending: false }).limit(200);
    const ids = (profiles ?? []).map(p => p.id);
    const { data: roles } = await supabase.from('user_roles').select('user_id, role').in('user_id', ids.length ? ids : ['00000000-0000-0000-0000-000000000000']);
    const roleMap = new Map<string, string>(); (roles ?? []).forEach(r => roleMap.set(r.user_id, String(r.role)));
    setUsers((profiles ?? []).map(p => ({ id: p.id, email: p.email, first_name: p.first_name, last_name: p.last_name, role: roleMap.get(p.id) ?? 'patient' }))); setLoading(false);
  };
  useEffect(() => { if (canManage) void loadDirectory(); }, [canManage]);
  const assignRole = async (userId: string, role: RoleValue) => {
    const { error } = await supabase.rpc('set_hms_user_role', { _target_user_id: userId, _role: role }); if (error) return toast({ title: 'Failed', description: error.message, variant: 'destructive' });
    toast({ title: 'Role updated', description: `Set to ${role}` }); void loadDirectory();
  };
  const promoteByEmail = async (e: React.FormEvent) => {
    e.preventDefault(); if (!searchEmail.trim()) return;
    const { data: profile } = await supabase.from('profiles').select('id').eq('email', searchEmail.trim()).maybeSingle();
    if (!profile) return toast({ title: 'User not found', description: 'Ask the user to sign up first, then assign the role.', variant: 'destructive' });
    await assignRole(profile.id, newRole); setSearchEmail('');
  };
  if (!user) return null;
  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h1 className="text-2xl font-heading font-bold">Admin User Management</h1><p className="text-muted-foreground">Assign roles and manage staff access.</p></div><div className="inline-flex items-center gap-2 rounded-2xl border border-border bg-background p-3"><ShieldCheck className="w-5 h-5 text-success" /><span className="text-sm text-muted-foreground">Roles are stored separately from profiles.</span></div></div>
    {!canManage && <div className="rounded-2xl border border-warning/20 bg-warning/10 p-4 text-sm text-warning">You must be an admin to manage users.</div>}
    {canManage && <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
      <div className="card-medical p-6"><div className="flex items-center justify-between mb-4"><div><h2 className="text-lg font-semibold">Staff & Patient Directory</h2><p className="text-sm text-muted-foreground">Assign the clinical role appropriate to each user.</p></div><UserPlus className="w-5 h-5 text-primary" /></div><div className="space-y-3">{loading && <p className="text-sm text-muted-foreground">Loading…</p>}{users.map(u => <div key={u.id} className="rounded-2xl border border-border p-4 flex items-center justify-between gap-3"><div><p className="font-medium">{u.first_name || u.last_name ? `${u.first_name ?? ''} ${u.last_name ?? ''}` : 'Unnamed'}</p><p className="text-xs text-muted-foreground">{u.email}</p></div><select value={u.role} onChange={e => void assignRole(u.id, e.target.value)} className="rounded-full bg-primary/10 px-3 py-1 text-xs font-semibold text-primary border-none">{availableRoles.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}</select></div>)}{!loading && users.length === 0 && <p className="text-sm text-muted-foreground">No users yet.</p>}</div></div>
      <div className="card-medical p-6"><div className="flex items-center justify-between mb-4"><div><h2 className="text-lg font-semibold">Promote a User</h2><p className="text-sm text-muted-foreground">User must sign up first.</p></div><Settings className="w-5 h-5 text-warning" /></div><form onSubmit={promoteByEmail} className="space-y-4"><input type="email" value={searchEmail} onChange={e => setSearchEmail(e.target.value)} className="input-medical w-full" placeholder="user@example.com" required /><select value={newRole} onChange={e => setNewRole(e.target.value)} className="input-medical w-full">{availableRoles.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}</select><button type="submit" className="btn-primary w-full">Assign Role</button></form></div>
    </div>}
    <div className="rounded-3xl border border-border bg-background/60 p-5"><div className="flex items-center gap-3 text-sm text-muted-foreground"><CheckCircle2 className="w-4 h-4" /><span>Role changes are database-backed; privileged access remains controlled by RLS.</span></div></div>
  </div>;
}
