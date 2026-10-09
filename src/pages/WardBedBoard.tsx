// @ts-nocheck -- schema types lag behind live database functions; runtime unaffected
import RefreshButton from '@/components/ui/RefreshButton';
import { searchPatientDirectory } from '@/lib/patientDirectory';
import { useEffect, useState } from 'react';
import { BedDouble, Plus,  Building2, Link2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { notifyMasterDataChanged, subscribeMasterDataChanged } from '@/lib/masterDataEvents';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';

type Ward = {
  id: string;
  name: string;
  code: string;
  specialty: string | null;
  gender_policy: string;
  active: boolean;
  facility_id: string | null;
  facility_name?: string | null;
  is_legacy?: boolean;
  legacy_id?: string | null;
};
type Bed = {
  id: string;
  ward_id: string;
  bed_number: string;
  status: string;
  patient_id: string | null;
  admission_id: string | null;
  facility_id: string | null;
};
type Patient = { id: string; patient_code: string; first_name: string; last_name: string };
type Facility = { id: string; name: string; facility_code: string | null; facility_type?: string | null };

const managementRoles = ['admin', 'it_admin', 'system_superuser'];

export default function WardBedBoard() {
  const { user } = useAuth();
  const canManage = managementRoles.includes(String(user?.role));
  const [wards, setWards] = useState<Ward[]>([]);
  const [beds, setBeds] = useState<Bed[]>([]);
  const [patients, setPatients] = useState<Patient[]>([]);
  const [facilities, setFacilities] = useState<Facility[]>([]);
  const [busy, setBusy] = useState(false);
  const [ward, setWard] = useState({ name: '', code: '', specialty: '', gender_policy: 'mixed', facility_id: '' });
  const [assignment, setAssignment] = useState<Record<string, string>>({});
  const [transferTarget, setTransferTarget] = useState<Record<string, string>>({});
  const [facilityChoice, setFacilityChoice] = useState<Record<string, string>>({});

  const load = async () => {
    const [workspace, patientsResult] = await Promise.all([
      supabase.rpc('get_ward_management_workspace', { _limit: 1000 } as never),
      searchPatientDirectory('', 500),
    ]);
    if (workspace.error || patientsResult.error) {
      toast({ title: 'Unable to load ward management', description: (workspace.error || patientsResult.error)?.message, variant: 'destructive' });
      return;
    }
    const payload = (workspace.data ?? {}) as { wards?: Ward[]; beds?: Bed[]; facilities?: Facility[] };
    setPatients((patientsResult.data ?? []) as Patient[]);
    setWards(payload.wards ?? []);
    setBeds(payload.beds ?? []);
    setFacilities(payload.facilities ?? []);
  };

  useEffect(() => {
    void load();
    return subscribeMasterDataChanged(['wards', 'beds'], () => void load());
  }, []);

  const createWard = async () => {
    if (!ward.name.trim() || !ward.code.trim() || !ward.facility_id) return;
    setBusy(true);
    const { error } = await supabase.rpc('create_ward_unit', {
      _name: ward.name.trim(),
      _code: ward.code.trim(),
      _specialty: ward.specialty.trim() || null,
      _gender_policy: ward.gender_policy,
      _facility_id: ward.facility_id,
    } as never);
    setBusy(false);
    if (error) {
      toast({ title: 'Ward creation failed', description: error.message, variant: 'destructive' });
      return;
    }
    setWard({ name: '', code: '', specialty: '', gender_policy: 'mixed', facility_id: ward.facility_id });
    toast({ title: 'Ward created', description: 'The ward is now part of the canonical ward configuration.' });
    notifyMasterDataChanged('wards');
    void load();
  };

  const assignFacility = async (ward: Ward) => {
    const facilityId = facilityChoice[ward.id];
    if (!facilityId) return;
    setBusy(true);
    const rpc = ward.is_legacy ? 'import_legacy_ward' : 'assign_ward_unit_facility';
    const args = ward.is_legacy
      ? { _legacy_ward_id: ward.legacy_id, _facility_id: facilityId }
      : { _ward_id: ward.id, _facility_id: facilityId };
    const { error } = await supabase.rpc(rpc as never, args as never);
    setBusy(false);
    if (error) {
      toast({ title: 'Facility assignment failed', description: error.message, variant: 'destructive' });
      return;
    }
    toast({ title: 'Facility assigned' });
    notifyMasterDataChanged('wards');
    void load();
  };

  const addBed = async (wardId: string) => {
    const number = window.prompt('Bed number');
    if (!number?.trim()) return;
    setBusy(true);
    const { error } = await supabase.rpc('create_ward_bed', { _ward_id: wardId, _bed_number: number.trim() } as never);
    setBusy(false);
    if (error) {
      toast({ title: 'Bed creation failed', description: error.message, variant: 'destructive' });
      return;
    }
    toast({ title: 'Bed added', description: 'The bed is now stored against the ward and facility.' });
    notifyMasterDataChanged('beds');
    void load();
  };

  const assign = async (bedId: string) => {
    const patientId = assignment[bedId];
    if (!patientId) return;
    setBusy(true);
    const { error } = await supabase.rpc('assign_ward_bed', { _bed_id: bedId, _patient_id: patientId, _admission_id: null } as never);
    setBusy(false);
    if (error) {
      toast({ title: 'Assignment failed', description: error.message, variant: 'destructive' });
      return;
    }
    setAssignment((current) => { const next = { ...current }; delete next[bedId]; return next; });
    toast({ title: 'Bed assigned' });
    notifyMasterDataChanged('beds');
    void load();
  };

  const transfer = async (bedId: string) => {
    const targetId = transferTarget[bedId];
    const source = beds.find((b) => b.id === bedId);
    if (!source?.admission_id || !targetId) return;
    setBusy(true);
    const { error } = await supabase.rpc('transfer_inpatient_bed', { _admission_id: source.admission_id, _target_bed_id: targetId, _summary: 'Bed transfer from ward board' } as never);
    setBusy(false);
    if (error) {
      toast({ title: 'Transfer failed', description: error.message, variant: 'destructive' });
      return;
    }
    setTransferTarget((current) => { const next = { ...current }; delete next[bedId]; return next; });
    toast({ title: 'Patient transferred' });
    notifyMasterDataChanged('beds');
    void load();
  };

  const release = async (bedId: string) => {
    setBusy(true);
    const { error } = await supabase.rpc('release_ward_bed', { _bed_id: bedId, _notes: 'Released from ward board' } as never);
    setBusy(false);
    if (error) {
      toast({ title: 'Release failed', description: error.message, variant: 'destructive' });
      return;
    }
    toast({ title: 'Bed moved to cleaning' });
    notifyMasterDataChanged('beds');
    void load();
  };

  const patientName = (id: string | null) => {
    const patient = patients.find((p) => p.id === id);
    return patient ? `${patient.patient_code} — ${patient.first_name} ${patient.last_name}` : 'Occupied patient';
  };

  const availableCount = beds.filter((b) => b.status === 'available').length;
  const occupiedCount = beds.filter((b) => b.status === 'occupied').length;
  const cleaningCount = beds.filter((b) => b.status === 'cleaning').length;

  return (
    <OperationalWorklistShell
      icon={BedDouble}
      eyebrow="Inpatient capacity"
      title="Ward & Bed Management"
      description="Canonical ward and bed configuration, capacity visibility, patient assignment, movement and release."
      actions={<RefreshButton onClick={() => void load()} loading={busy} label="Refresh ward and bed management" />}
      counters={[
        { label: 'Available beds', value: availableCount, tone: 'text-success' },
        { label: 'Occupied beds', value: occupiedCount },
        { label: 'Cleaning beds', value: cleaningCount, tone: 'text-warning' },
        { label: 'Wards', value: wards.length },
      ]}
      beforeList={canManage ? (
        <section className="card-medical p-5">
          <div className="flex flex-wrap items-center justify-between gap-3 mb-4">
            <div>
              <h2 className="font-semibold flex items-center gap-2"><Building2 className="h-4 w-4" />Ward configuration</h2>
              <p className="text-xs text-muted-foreground">Admin, IT Admin and System Superuser control the structural ward/bed catalogue. Clinical users operate configured capacity without creating structural records.</p>
            </div>
            <span className="rounded-full bg-muted px-3 py-1 text-xs">Admin / IT Admin / System Superuser</span>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-6 gap-3">
            <label className="text-xs">Ward name<input aria-label="Ward name" placeholder="Ward name" value={ward.name} onChange={(e) => setWard({ ...ward, name: e.target.value })} className="input-medical mt-1 w-full" /></label>
            <label className="text-xs">Code<input aria-label="Ward code" placeholder="Code" value={ward.code} onChange={(e) => setWard({ ...ward, code: e.target.value })} className="input-medical mt-1 w-full" /></label>
            <label className="text-xs">Specialty<input aria-label="Ward specialty" placeholder="Specialty" value={ward.specialty} onChange={(e) => setWard({ ...ward, specialty: e.target.value })} className="input-medical mt-1 w-full" /></label>
            <label className="text-xs">Gender policy<select aria-label="Ward gender policy" value={ward.gender_policy} onChange={(e) => setWard({ ...ward, gender_policy: e.target.value })} className="input-medical mt-1 w-full"><option value="mixed">Mixed</option><option value="male">Male</option><option value="female">Female</option></select></label>
            <label className="text-xs">Facility<select aria-label="Ward facility" value={ward.facility_id} onChange={(e) => setWard({ ...ward, facility_id: e.target.value })} className="input-medical mt-1 w-full"><option value="">Select facility…</option>{facilities.map((facility) => <option key={facility.id} value={facility.id}>{facility.name}{facility.facility_code ? ` · ${facility.facility_code}` : ''}</option>)}</select></label>
            <button type="button" disabled={busy || !ward.facility_id} onClick={() => void createWard()} className="btn-primary self-end disabled:opacity-50"><Plus className="inline w-4 h-4 mr-1" />Create ward</button>
          </div>
        </section>
      ) : null}
      listTitle="Ward capacity worklist"
      listDescription="Configured wards remain grouped with their beds so operational and structural context stays together."
      listMeta={`${wards.length} ward${wards.length === 1 ? '' : 's'} · ${beds.length} bed${beds.length === 1 ? '' : 's'}`}
      empty={wards.length === 0}
      emptyIcon={BedDouble}
      emptyTitle="No wards configured"
      emptyDescription={canManage ? 'Create a ward above to begin configuring inpatient capacity.' : 'No ward configuration is available for your facility.'}
    >
      <div className="grid gap-4 p-4 md:grid-cols-2 xl:grid-cols-3">
        {wards.map((w) => {
          const wardBeds = beds.filter((b) => b.ward_id === w.id);
          const occupied = wardBeds.filter((b) => b.status === 'occupied').length;
          const legacyUnscoped = !w.facility_id;
          return (
            <section key={w.id} className="rounded-xl border border-border bg-card p-4">
              <div className="flex justify-between items-center mb-3 gap-3">
                <div className="min-w-0">
                  <h2 className="font-semibold truncate">{w.name}</h2>
                  <p className="text-xs text-muted-foreground truncate">{w.code}{w.specialty ? ` · ${w.specialty}` : ''} · {w.gender_policy}</p>
                  <p className="mt-1 text-[11px] text-muted-foreground">{w.facility_name ?? 'Facility not assigned'}</p>
                </div>
                <span className="shrink-0 rounded-full bg-muted px-2.5 py-1 text-xs font-semibold">{occupied}/{wardBeds.length}</span>
              </div>

              {canManage && legacyUnscoped && (
                <div className="mb-3 rounded-lg border border-dashed border-border p-3">
                  <p className="text-xs font-medium">Legacy ward requires canonical facility import</p>
                  <div className="mt-2 flex gap-2">
                    <select aria-label={`Assign facility to ward ${w.name}`} value={facilityChoice[w.id] || ''} onChange={(e) => setFacilityChoice((current) => ({ ...current, [w.id]: e.target.value }))} className="input-medical min-w-0 flex-1"><option value="">Select facility…</option>{facilities.map((facility) => <option key={facility.id} value={facility.id}>{facility.name}</option>)}</select>
                    <button type="button" disabled={busy || !facilityChoice[w.id]} onClick={() => void assignFacility(w)} className="btn-secondary text-xs disabled:opacity-50"><Link2 className="inline h-3.5 w-3.5 mr-1" />Import</button>
                  </div>
                </div>
              )}

              {canManage && !legacyUnscoped && <button type="button" disabled={busy} onClick={() => void addBed(w.id)} className="btn-secondary mb-3 text-xs disabled:opacity-50">Add bed</button>}
              <div className="space-y-2">
                {wardBeds.length === 0 ? <p className="text-sm text-muted-foreground">No beds configured.</p> : wardBeds.map((b) => (
                  <div key={b.id} className="rounded-xl border border-border p-3">
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                      <div className="min-w-0"><span className="font-medium">Bed {b.bed_number}</span><div className="mt-1 text-xs text-muted-foreground truncate">{b.status}{b.patient_id ? ` · ${patientName(b.patient_id)}` : ''}</div></div>
                      {b.status === 'available' && !canManage ? (
                        <div className="flex gap-2 w-full sm:w-auto"><select aria-label={`Assign patient to bed ${b.bed_number}`} value={assignment[b.id] || ''} onChange={(e) => setAssignment((current) => ({ ...current, [b.id]: e.target.value }))} className="input-medical min-w-0 flex-1 sm:w-52"><option value="">Select patient…</option>{patients.map((p) => <option key={p.id} value={p.id}>{p.patient_code} — {p.first_name} {p.last_name}</option>)}</select><button type="button" disabled={busy || !assignment[b.id]} onClick={() => void assign(b.id)} className="btn-primary text-xs disabled:opacity-50">Assign</button></div>
                      ) : b.status === 'occupied' ? (
                        <div className="flex flex-wrap gap-2 w-full sm:w-auto"><select aria-label={`Transfer patient from bed ${b.bed_number}`} value={transferTarget[b.id] || ''} onChange={(e) => setTransferTarget((current) => ({ ...current, [b.id]: e.target.value }))} className="input-medical min-w-0 sm:w-44"><option value="">Transfer to…</option>{beds.filter((target) => target.status === 'available' && target.id !== b.id).map((target) => <option key={target.id} value={target.id}>{wards.find((candidate) => candidate.id === target.ward_id)?.name ?? 'Ward'} · {target.bed_number}</option>)}</select><button type="button" disabled={busy || !transferTarget[b.id] || !b.admission_id} onClick={() => void transfer(b.id)} className="btn-primary text-xs disabled:opacity-50">Transfer</button><button type="button" disabled={busy} onClick={() => void release(b.id)} className="btn-secondary text-xs">Release</button></div>
                      ) : null}
                    </div>
                  </div>
                ))}
              </div>
            </section>
          );
        })}
      </div>
    </OperationalWorklistShell>
  );
}