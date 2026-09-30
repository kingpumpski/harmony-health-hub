import { useEffect, useMemo, useState } from 'react';
import { ShieldCheck, Save, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { getDefaultPermissions, type Permission } from '@/lib/permissions';
import type { UserRole } from '@/types';

const roles: { value: UserRole; label: string }[] = [
  { value: 'it_admin', label: 'IT Admin' },
  { value: 'admin', label: 'Administrator' }, { value: 'practitioner', label: 'Practitioner' }, { value: 'nurse', label: 'Nurse' },
  { value: 'specialist_nurse', label: 'Specialist Nurse' }, { value: 'midwife', label: 'Midwife' }, { value: 'radiologist', label: 'Radiologist' }, { value: 'radiology_technician', label: 'Radiology Technician' },
  { value: 'lab_technician', label: 'Lab Technician' }, { value: 'pharmacist', label: 'Pharmacist' }, { value: 'accountant', label: 'Accountant' },
  { value: 'front_desk', label: 'Front Desk' }, { value: 'canteen', label: 'Canteen' }, { value: 'patient', label: 'Patient' },
];

interface PermissionRow { permission_key: string; description: string; is_active: boolean }

export default function RolePermissions() {
  const { user, refreshUser } = useAuth();
  const [selectedRole, setSelectedRole] = useState<UserRole>('practitioner');
  const [catalog, setCatalog] = useState<PermissionRow[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set(getDefaultPermissions('practitioner')));
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = async () => {
    if (user?.role !== 'admin') return;
    setLoading(true);
    const [{ data: permissions, error: permissionError }, { data: mappings, error: mappingError }] = await Promise.all([
      supabase.from('permissions').select('permission_key, description, is_active').eq('is_active', true).order('permission_key'),
      supabase.from('role_permissions').select('permission_key').eq('role', selectedRole),
    ]);
    if (permissionError || mappingError) {
      setLoading(false);
      toast({ title: 'Permissions unavailable', description: permissionError?.message ?? mappingError?.message ?? 'Unable to load permission catalog.', variant: 'destructive' });
      return;
    }
    setCatalog((permissions ?? []) as PermissionRow[]);
    const mapped = new Set((mappings ?? []).map(row => row.permission_key));
    setSelected(selectedRole === 'admin' ? new Set((permissions ?? []).map(row => row.permission_key)) : (mapped.size ? mapped : new Set(getDefaultPermissions(selectedRole))));
    setLoading(false);
  };

  useEffect(() => { void load(); }, [selectedRole, user?.role]);

  const grouped = useMemo(() => {
    const groups = new Map<string, PermissionRow[]>();
    catalog.forEach(item => {
      const prefix = item.permission_key.split('_')[0] || 'general';
      const group = groups.get(prefix) ?? [];
      group.push(item);
      groups.set(prefix, group);
    });
    return [...groups.entries()];
  }, [catalog]);

  const toggle = (key: string) => setSelected(previous => {
    const next = new Set(previous);
    if (next.has(key)) next.delete(key); else next.add(key);
    return next;
  });

  const resetDefaults = () => setSelected(selectedRole === 'admin' ? new Set(catalog.map(item => item.permission_key)) : new Set(getDefaultPermissions(selectedRole)));

  const save = async () => {
    if (user?.role !== 'admin') return;
    setSaving(true);
    const { data, error } = await supabase.rpc('replace_role_permissions' as never, {
      _role: selectedRole,
      _permission_keys: [...selected],
    } as never);
    setSaving(false);
    if (error || data === false) {
      toast({ title: 'Save failed', description: error?.message ?? 'The role permission update was rejected.', variant: 'destructive' });
      return;
    }
    toast({ title: 'Permissions updated', description: roles.find(role => role.value === selectedRole)?.label + ' permissions have been saved.' });
    if (user.role === selectedRole) await refreshUser();
    await load();
  };

  if (user?.role !== 'admin') return <div className="card-medical p-6"><h1 className="text-xl font-semibold">Administrator access required</h1><p className="mt-2 text-sm text-muted-foreground">Only administrators can configure application navigation permissions.</p></div>;

  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div><h1 className="text-2xl font-heading font-bold">Roles & Permissions</h1><p className="text-muted-foreground">Configure which application areas appear for each role. Database authorization and RLS remain authoritative.</p></div>
      <div className="flex items-center gap-2 rounded-2xl border border-border bg-background p-3 text-sm"><ShieldCheck className="h-5 w-5 text-success" />Navigation permissions are not a security bypass.</div>
    </div>
    <div className="card-medical p-5">
      <label className="text-sm font-medium">Role</label>
      <select value={selectedRole} onChange={event => setSelectedRole(event.target.value as UserRole)} className="input-medical mt-2 max-w-sm">
        {roles.map(role => <option key={role.value} value={role.value}>{role.label}</option>)}
      </select>
    </div>
    <div className="card-medical p-5">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div><h2 className="text-lg font-semibold">Application permissions</h2>{selectedRole === 'admin' && <span className="text-xs text-success">Administrator is always granted every active permission.</span>}<p className="text-sm text-muted-foreground">{selected.size} enabled</p></div>
        <div className="flex gap-2"><button type="button" onClick={resetDefaults} className="btn-secondary"><RefreshCw className="h-4 w-4" />Restore defaults</button><button type="button" onClick={() => void save()} disabled={saving || loading} className="btn-primary"><Save className="h-4 w-4" />{saving ? 'Saving…' : 'Save permissions'}</button></div>
      </div>
      {loading ? <p className="py-8 text-sm text-muted-foreground">Loading permission catalog…</p> : <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {grouped.map(([group, items]) => <section key={group} className="rounded-2xl border border-border p-4">
          <h3 className="mb-3 text-sm font-semibold capitalize">{group.replace(/_/g, ' ')}</h3>
          <div className="space-y-2">{items.map(item => <label key={item.permission_key} className="flex cursor-pointer items-start gap-3 rounded-lg p-2 hover:bg-muted/50">
            <input type="checkbox" checked={selected.has(item.permission_key)} onChange={() => toggle(item.permission_key)} disabled={selectedRole === 'admin'} className="mt-1 h-4 w-4" />
            <span><span className="block text-sm font-medium">{item.permission_key.replace(/_/g, ' ')}</span><span className="block text-xs text-muted-foreground">{item.description}</span></span>
          </label>)}</div>
        </section>)}
      </div>}
    </div>
  </div>;
}
