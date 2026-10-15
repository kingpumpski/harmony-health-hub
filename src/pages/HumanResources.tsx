import { useCallback, useEffect, useMemo, useState } from 'react';
import { Archive, ArchiveRestore, BriefcaseBusiness, Pencil, Plus, RefreshCw, Search, Users } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';

type Employee = {
  id: string;
  employee_number: string;
  first_name: string;
  last_name: string;
  email: string | null;
  phone: string | null;
  department: string | null;
  job_title: string;
  employment_type: string;
  employment_status: string;
  base_salary: number;
  pay_frequency: string;
  start_date: string;
  archived_at: string | null;
};

type EmployeeDraft = {
  employee_number: string;
  first_name: string;
  last_name: string;
  email: string;
  phone: string;
  department: string;
  job_title: string;
  employment_type: string;
  employment_status: string;
  base_salary: string;
  pay_frequency: string;
  start_date: string;
};

const db = supabase as any;
const employeeFields = 'id,employee_number,first_name,last_name,email,phone,department,job_title,employment_type,employment_status,base_salary,pay_frequency,start_date,archived_at';
const emptyDraft = (): EmployeeDraft => ({
  employee_number: '', first_name: '', last_name: '', email: '', phone: '', department: '',
  job_title: '', employment_type: 'full_time', employment_status: 'active',
  base_salary: '', pay_frequency: 'monthly', start_date: new Date().toISOString().slice(0, 10),
});

async function activeFacilityId() {
  const { data, error } = await db.rpc('current_user_facility_id');
  if (error || !data) throw new Error(error?.message || 'No active facility is selected.');
  return data as string;
}

export default function HumanResources() {
  const { user } = useAuth();
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [editorOpen, setEditorOpen] = useState(false);
  const [editing, setEditing] = useState<Employee | null>(null);
  const [archiveTarget, setArchiveTarget] = useState<Employee | null>(null);
  const [draft, setDraft] = useState<EmployeeDraft>(emptyDraft);
  const [search, setSearch] = useState('');
  const [showArchived, setShowArchived] = useState(false);

  const canManage = ['admin', 'it_admin', 'accountant'].includes(user?.role ?? '');
  const canArchive = ['admin', 'it_admin'].includes(user?.role ?? '');

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await db.from('hr_employees')
      .select(employeeFields)
      .order('last_name')
      .order('first_name');
    if (error) toast.error(`Unable to load employee records: ${error.message}`);
    else setEmployees((data ?? []) as Employee[]);
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const visibleEmployees = useMemo(() => {
    const normalizedSearch = search.trim().toLowerCase();
    return employees.filter((employee) => {
      if (Boolean(employee.archived_at) !== showArchived) return false;
      if (!normalizedSearch) return true;
      return [
        employee.employee_number, employee.first_name, employee.last_name,
        employee.department, employee.job_title, employee.email,
      ].some((value) => value?.toLowerCase().includes(normalizedSearch));
    });
  }, [employees, search, showArchived]);

  const openNew = () => {
    setEditing(null);
    setDraft(emptyDraft());
    setEditorOpen(true);
  };

  const openEdit = (employee: Employee) => {
    setEditing(employee);
    setDraft({
      employee_number: employee.employee_number,
      first_name: employee.first_name,
      last_name: employee.last_name,
      email: employee.email ?? '',
      phone: employee.phone ?? '',
      department: employee.department ?? '',
      job_title: employee.job_title,
      employment_type: employee.employment_type,
      employment_status: employee.employment_status,
      base_salary: String(employee.base_salary ?? 0),
      pay_frequency: employee.pay_frequency,
      start_date: employee.start_date,
    });
    setEditorOpen(true);
  };

  const save = async () => {
    if (!canManage) return;
    const employeeNumber = draft.employee_number.trim();
    const firstName = draft.first_name.trim();
    const lastName = draft.last_name.trim();
    const jobTitle = draft.job_title.trim();
    const baseSalary = Number(draft.base_salary || 0);
    if (!employeeNumber || !firstName || !lastName || !jobTitle || !draft.start_date) {
      toast.error('Employee number, name, job title and start date are required.');
      return;
    }
    if (!Number.isFinite(baseSalary) || baseSalary < 0) {
      toast.error('Base salary must be a valid non-negative amount.');
      return;
    }

    setSaving(true);
    try {
      const payload = {
        employee_number: employeeNumber,
        first_name: firstName,
        last_name: lastName,
        email: draft.email.trim() || null,
        phone: draft.phone.trim() || null,
        department: draft.department.trim() || null,
        job_title: jobTitle,
        employment_type: draft.employment_type,
        employment_status: draft.employment_status,
        base_salary: baseSalary,
        pay_frequency: draft.pay_frequency,
        start_date: draft.start_date,
        updated_at: new Date().toISOString(),
      };
      const query = editing
        ? db.from('hr_employees').update(payload).eq('id', editing.id)
        : db.from('hr_employees').insert({
          ...payload,
          facility_id: await activeFacilityId(),
          created_by: user?.id,
        });
      const { error } = await query;
      if (error) throw new Error(error.message);
      toast.success(editing ? 'Employee record updated.' : 'Employee record created.');
      setEditorOpen(false);
      await load();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Unable to save employee record.');
    } finally {
      setSaving(false);
    }
  };

  const setArchived = async (employee: Employee) => {
    if (!canArchive || !user?.id) return;
    const archiving = !employee.archived_at;
    const { error } = await db.from('hr_employees')
      .update({
        archived_at: archiving ? new Date().toISOString() : null,
        archived_by: archiving ? user.id : null,
      })
      .eq('id', employee.id);
    if (error) {
      toast.error(`Unable to ${archiving ? 'archive' : 'restore'} employee: ${error.message}`);
      return;
    }
    toast.success(archiving ? 'Employee record archived.' : 'Employee record restored.');
    setArchiveTarget(null);
    await load();
  };

  const updateDraft = (key: keyof EmployeeDraft, value: string) => {
    setDraft((current) => ({ ...current, [key]: value }));
  };

  const field = (key: keyof EmployeeDraft, label: string, type = 'text') => (
    <label key={key} className="space-y-1 text-sm">
      <span className="font-medium">{label}</span>
      <input
        className="input-medical w-full"
        type={type}
        value={draft[key]}
        min={type === 'number' ? '0' : undefined}
        step={type === 'number' ? '0.01' : undefined}
        onChange={(event) => updateDraft(key, event.target.value)}
      />
    </label>
  );

  return (
    <div className="space-y-6 animate-fade-in">
      <header className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-heading font-bold">
            <BriefcaseBusiness className="h-6 w-6 text-primary" />Human Resources
          </h1>
          <p className="text-sm text-muted-foreground">Facility workforce directory and employment records.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button type="button" className="btn-secondary h-10 w-10 p-0" aria-label="Refresh employees" onClick={() => void load()}>
            <RefreshCw className="h-4 w-4" />
          </button>
          {canManage && <button type="button" className="btn-primary inline-flex gap-2" onClick={openNew}>
            <Plus className="h-4 w-4" />Add employee
          </button>}
        </div>
      </header>

      <section className="card-medical overflow-hidden">
        <div className="flex flex-col gap-3 border-b p-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-2 font-semibold">
            <Users className="h-4 w-4" />Workforce directory
            <span className="text-xs text-muted-foreground">({visibleEmployees.length})</span>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <label className="relative block">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <input className="input-medical pl-9" aria-label="Search employees" placeholder="Search employees" value={search} onChange={(event) => setSearch(event.target.value)} />
            </label>
            {canArchive && <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={showArchived} onChange={(event) => setShowArchived(event.target.checked)} />
              Show archived
            </label>}
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="table-medical w-full">
            <thead><tr><th>Employee</th><th>Department</th><th>Position</th><th>Employment</th><th>Pay</th><th>Start date</th>{canManage && <th className="text-right">Actions</th>}</tr></thead>
            <tbody>
              {loading && <tr><td colSpan={canManage ? 7 : 6} className="p-8 text-center text-sm text-muted-foreground">Loading workforce…</td></tr>}
              {!loading && visibleEmployees.map((employee) => (
                <tr key={employee.id}>
                  <td><div className="font-medium">{employee.first_name} {employee.last_name}</div><div className="text-xs text-muted-foreground">{employee.employee_number}{employee.email ? ` · ${employee.email}` : ''}</div></td>
                  <td>{employee.department || '—'}</td>
                  <td>{employee.job_title}</td>
                  <td><span className={employee.archived_at ? 'badge-info' : employee.employment_status === 'active' ? 'badge-success' : 'badge-warning'}>{employee.archived_at ? 'Archived' : employee.employment_status.replace(/_/g, ' ')}</span><div className="mt-1 text-xs text-muted-foreground">{employee.employment_type.replace(/_/g, ' ')}</div></td>
                  <td>GHS {Number(employee.base_salary || 0).toLocaleString(undefined, { minimumFractionDigits: 2 })} / {employee.pay_frequency}</td>
                  <td>{employee.start_date}</td>
                  {canManage && <td><div className="flex justify-end gap-2">
                    {!employee.archived_at && <button type="button" className="btn-secondary h-9" aria-label={`Edit ${employee.first_name} ${employee.last_name}`} onClick={() => openEdit(employee)}><Pencil className="h-4 w-4" /><span className="sr-only">Edit</span></button>}
                    {canArchive && <button type="button" className="btn-secondary h-9" aria-label={`${employee.archived_at ? 'Restore' : 'Archive'} ${employee.first_name} ${employee.last_name}`} onClick={() => setArchiveTarget(employee)}>
                      {employee.archived_at ? <ArchiveRestore className="h-4 w-4" /> : <Archive className="h-4 w-4" />}
                      <span className="sr-only">{employee.archived_at ? 'Restore' : 'Archive'}</span>
                    </button>}
                  </div></td>}
                </tr>
              ))}
              {!loading && visibleEmployees.length === 0 && <tr><td colSpan={canManage ? 7 : 6} className="p-10 text-center text-sm text-muted-foreground">
                {showArchived ? 'No archived employee records.' : 'No employee records match this search.'}
              </td></tr>}
            </tbody>
          </table>
        </div>
      </section>

      <Dialog open={editorOpen} onOpenChange={setEditorOpen}>
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-3xl">
          <DialogHeader>
            <DialogTitle>{editing ? 'Edit employee record' : 'Add employee record'}</DialogTitle>
            <DialogDescription>Update workforce details for the active facility. Payroll history remains linked to this employee.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {field('employee_number', 'Employee number')}
            {field('first_name', 'First name')}
            {field('last_name', 'Last name')}
            {field('email', 'Email', 'email')}
            {field('phone', 'Phone', 'tel')}
            {field('department', 'Department')}
            {field('job_title', 'Job title')}
            {field('start_date', 'Start date', 'date')}
            {field('base_salary', 'Base salary (GHS)', 'number')}
            <label className="space-y-1 text-sm"><span className="font-medium">Employment type</span><select className="input-medical w-full" value={draft.employment_type} onChange={(event) => updateDraft('employment_type', event.target.value)}><option value="full_time">Full time</option><option value="part_time">Part time</option><option value="contract">Contract</option><option value="casual">Casual</option><option value="intern">Intern</option></select></label>
            <label className="space-y-1 text-sm"><span className="font-medium">Employment status</span><select className="input-medical w-full" value={draft.employment_status} onChange={(event) => updateDraft('employment_status', event.target.value)}><option value="active">Active</option><option value="on_leave">On leave</option><option value="suspended">Suspended</option><option value="terminated">Terminated</option></select></label>
            <label className="space-y-1 text-sm"><span className="font-medium">Pay frequency</span><select className="input-medical w-full" value={draft.pay_frequency} onChange={(event) => updateDraft('pay_frequency', event.target.value)}><option value="monthly">Monthly</option><option value="biweekly">Biweekly</option><option value="weekly">Weekly</option></select></label>
          </div>
          <DialogFooter>
            <button type="button" className="btn-secondary" onClick={() => setEditorOpen(false)}>Cancel</button>
            <button type="button" className="btn-primary" disabled={saving} onClick={() => void save()}>{saving ? 'Saving…' : editing ? 'Save changes' : 'Create employee'}</button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <AlertDialog open={Boolean(archiveTarget)} onOpenChange={(open) => { if (!open) setArchiveTarget(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{archiveTarget?.archived_at ? 'Restore employee record?' : 'Archive employee record?'}</AlertDialogTitle>
            <AlertDialogDescription>
              {archiveTarget?.archived_at
                ? 'This employee will return to the active workforce directory. Prior payroll records are retained.'
                : 'The employee will be hidden from the active directory and excluded from future payroll generation. Existing payroll records are retained.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={(event) => { event.preventDefault(); if (archiveTarget) void setArchived(archiveTarget); }}>
              {archiveTarget?.archived_at ? 'Restore record' : 'Archive record'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
