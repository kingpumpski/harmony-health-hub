import { useMemo, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { UserPlus, ShieldCheck, Settings, CheckCircle2 } from 'lucide-react';

const availableRoles = [
  { value: 'admin', label: 'Admin' },
  { value: 'practitioner', label: 'Doctor' },
  { value: 'nurse', label: 'Nurse' },
  { value: 'lab_technician', label: 'Lab Technician' },
  { value: 'pharmacist', label: 'Pharmacist' },
  { value: 'accountant', label: 'Accountant' },
  { value: 'front_desk', label: 'Front Desk' },
];

export default function AdminUsers() {
  const { user } = useAuth();
  const [users, setUsers] = useState([
    { id: '1', name: 'Pumpski Admin', email: 'pumpski6@gmail.com', role: 'admin' },
    { id: '2', name: 'Dr. Sarah Johnson', email: 'doctor@medicarepro.com', role: 'practitioner' },
  ]);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [role, setRole] = useState('practitioner');
  const [message, setMessage] = useState('');

  const canCreate = user?.role === 'admin';

  const handleCreate = (e: React.FormEvent) => {
    e.preventDefault();
    if (!canCreate) return;
    if (!name || !email) {
      setMessage('Name and email are required.');
      return;
    }
    const newUser = {
      id: `${users.length + 1}`,
      name,
      email,
      role,
    };
    setUsers((prev) => [newUser, ...prev]);
    setName('');
    setEmail('');
    setRole('practitioner');
    setMessage('User created successfully.');
  };

  const privilegedNote = useMemo(() => {
    if (!user) return '';
    return user.role === 'admin'
      ? 'As an admin, you may enroll staff and assign roles.'
      : 'Only admin users can create other users in the system.';
  }, [user]);

  if (!user) return null;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Admin User Management</h1>
          <p className="text-muted-foreground">Control staff enrollment, privileges, and system roles.</p>
        </div>
        <div className="inline-flex items-center gap-2 rounded-2xl border border-border bg-background p-3">
          <ShieldCheck className="w-5 h-5 text-success" />
          <span className="text-sm text-muted-foreground">Admin-only access ensures secure user provisioning.</span>
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
        <div className="card-medical p-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-semibold">Staff Directory</h2>
              <p className="text-sm text-muted-foreground">Existing system users and roles.</p>
            </div>
            <UserPlus className="w-5 h-5 text-primary" />
          </div>
          <div className="space-y-3">
            {users.map((staff) => (
              <div key={staff.id} className="rounded-2xl border border-border p-4 flex items-center justify-between gap-3">
                <div>
                  <p className="font-medium">{staff.name}</p>
                  <p className="text-xs text-muted-foreground">{staff.email}</p>
                </div>
                <span className="rounded-full bg-primary/10 px-3 py-1 text-xs font-semibold text-primary">{staff.role}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="card-medical p-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-semibold">Create New User</h2>
              <p className="text-sm text-muted-foreground">Only admin accounts can enroll staff.</p>
            </div>
            <Settings className="w-5 h-5 text-warning" />
          </div>
          {!canCreate && (
            <div className="rounded-2xl border border-warning/20 bg-warning/10 p-4 text-sm text-warning">
              You must be an admin to create new users.
            </div>
          )}
          <form onSubmit={handleCreate} className="space-y-4 mt-4">
            <div>
              <label className="block text-sm font-medium mb-2">Full Name</label>
              <input value={name} onChange={(e) => setName(e.target.value)} className="input-medical w-full" disabled={!canCreate} />
            </div>
            <div>
              <label className="block text-sm font-medium mb-2">Email Address</label>
              <input value={email} onChange={(e) => setEmail(e.target.value)} className="input-medical w-full" disabled={!canCreate} />
            </div>
            <div>
              <label className="block text-sm font-medium mb-2">Role</label>
              <select value={role} onChange={(e) => setRole(e.target.value)} className="input-medical w-full" disabled={!canCreate}>
                {availableRoles.map((roleItem) => (
                  <option key={roleItem.value} value={roleItem.value}>{roleItem.label}</option>
                ))}
              </select>
            </div>
            <button type="submit" className="btn-primary w-full" disabled={!canCreate}>
              Create User
            </button>
            {message && <p className="text-sm text-success">{message}</p>}
          </form>
        </div>
      </div>

      <div className="rounded-3xl border border-border bg-background/60 p-5">
        <div className="flex items-center gap-3 text-sm text-muted-foreground">
          <CheckCircle2 className="w-4 h-4" />
          <span>{privilegedNote}</span>
        </div>
      </div>
    </div>
  );
}
