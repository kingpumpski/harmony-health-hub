import { searchPatientDirectory } from '@/lib/patientDirectory';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, Search } from 'lucide-react';
import { toast } from 'sonner';
import { RecordList, StatusBadge } from '@/components/records/RecordList';
import PatientAvatar from '@/components/patients/PatientAvatar';

type Patient = { id:string; patient_code:string; first_name:string; last_name:string; phone:string|null; status:string|null };

function StaffMedicalRecords() {
  const navigate=useNavigate();
  const [patients,setPatients]=useState<Patient[]>([]);
  const [query,setQuery]=useState('');
  const [loading,setLoading]=useState(true);
  const load=async()=>{setLoading(true); const {data,error}=await searchPatientDirectory('',300); if(error) toast.error(error.message); else setPatients((data??[]) as Patient[]); setLoading(false);};
  useEffect(()=>{void load();},[]);
  const filtered=useMemo(()=>{const q=query.trim().toLowerCase(); if(!q)return patients; return patients.filter(p=>`${p.first_name} ${p.last_name} ${p.patient_code} ${p.phone??''}`.toLowerCase().includes(q));},[patients,query]);
  const columns=[{key:'patient',header:'Patient',render:(p:Patient)=><div className="flex items-center gap-3"><PatientAvatar name={`${p.first_name} ${p.last_name}`} size="sm"/><div><p className="font-medium">{p.first_name} {p.last_name}</p><p className="text-xs text-muted-foreground">{p.patient_code}</p></div></div>},{key:'phone',header:'Phone',hideBelow:'md' as const,render:(p:Patient)=>p.phone||'Not recorded'},{key:'status',header:'Status',render:(p:Patient)=><StatusBadge status={p.status||'active'}/> }];
  return <div className="space-y-6 animate-fade-in"><div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><FileText className="w-6 h-6 text-primary"/>Medical Records</h1><p className="text-muted-foreground">Open a patient chart and review the complete clinical record.</p></div><div className="card-medical p-4 flex items-center gap-3"><Search className="w-5 h-5 text-muted-foreground"/><input value={query} onChange={e=>setQuery(e.target.value)} className="input-medical flex-1" placeholder="Search by patient name, code or phone…" aria-label="Filter medical records"/></div><RecordList title="Patient medical records" description={`${filtered.length} patient record(s) available`} data={filtered} columns={columns} isLoading={loading} error={null} rowKey={p=>p.id} onRowClick={p=>navigate(`/patients/${p.id}`)} onRefresh={()=>void load()} emptyState={{title:query.trim()?'No matching patient records':'No patient records',description:query.trim()?'Try another patient name, code or phone number.':'No patient records are currently available to this workspace.'}}/></div>;
}

function PatientMedicalRecords(){
  const [snapshot,setSnapshot]=useState<any>(null);
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState<string|null>(null);
  const load=async()=>{
    setLoading(true); setError(null);
    const {data:identity,error:identityError}=await supabase.rpc('get_patient_portal_identity',{}, {get:true});
    const patient=Array.isArray(identity)?identity[0]:identity;
    if(identityError||!patient){setError(identityError?.message??'Your patient profile could not be identified.');setLoading(false);return;}
    const {data,error:snapshotError}=await supabase.rpc('get_patient_hub_clinical_snapshot',{_patient_id:patient.id},{get:true});
    if(snapshotError)setError(snapshotError.message); else setSnapshot(data??null);
    setLoading(false);
  };
  useEffect(()=>{void load();},[]);
  const rows=(v:any)=>Array.isArray(v)?v:[];
  if(loading)return <div className="card-medical p-5 text-sm text-muted-foreground">Loading medical records…</div>;
  if(error)return <div className="card-medical p-5"><p className="text-sm text-critical">{error}</p><button className="btn-secondary mt-3" onClick={()=>void load()}>Retry</button></div>;
  const sections=[
    ['Clinical encounters & clerking',snapshot?.encounters,(x:any)=><><b>{x.encounter_type||'Clinical encounter'}</b><p className="mt-1 whitespace-pre-wrap">{x.clerking_notes||x.symptoms||'No narrative note recorded.'}</p>{x.principal_diagnosis&&<p><b>Diagnosis:</b> {x.principal_diagnosis}</p>}{x.treatment_plan&&<p><b>Plan:</b> {x.treatment_plan}</p></>],
    ['Diagnoses',snapshot?.diagnoses,(x:any)=><><b>{x.diagnosis||'Diagnosis'}</b>{x.icd_code&&<span className="ml-2 text-xs text-muted-foreground">{x.icd_code}</span>}</>],
    ['Laboratory results',snapshot?.labs,(x:any)=><><b>{x.test_name||'Laboratory result'}</b><p className="mt-1 whitespace-pre-wrap">{x.result||x.result_data?.value||x.interpretation||'Result available'}</p></>],
    ['Radiology reports',snapshot?.imaging,(x:any)=><><b>{x.study_name||x.modality||'Imaging report'}</b><p className="mt-1 whitespace-pre-wrap">{x.impression||x.report||'Report available'}</p></>],
    ['Prescriptions & medicines',snapshot?.prescriptions,(x:any)=><><b>{x.medication||x.medication_name||'Medication'}</b><p className="mt-1">{[x.dosage,x.frequency,x.route,x.duration].filter(Boolean).join(' · ')}</p></>],
    ['Vital signs',snapshot?.vitals,(x:any)=><><b>{x.recorded_at?new Date(x.recorded_at).toLocaleString():'Recorded vitals'}</b><p className="mt-1">BP {x.systolic??'—'}/{x.diastolic??'—'} · Pulse {x.pulse_rate??'—'} · Temp {x.temperature??'—'} · SpO₂ {x.oxygen_saturation??'—'}%</p></>],
    ['Admissions & discharge history',snapshot?.admissions,(x:any)=><><b>{x.ward||'Inpatient admission'}</b><p className="mt-1">{x.status||'—'} · Admitted {x.admitted_at?new Date(x.admitted_at).toLocaleString():'—'}</p></>],
    ['Documents',snapshot?.documents,(x:any)=><><b>{x.file_name||x.document_type||'Patient document'}</b>{x.notes&&<p className="mt-1">{x.notes}</p>}</>]
  ];
  return <div className="space-y-6 animate-fade-in"><div><h1 className="text-2xl font-heading font-bold">Medical Records</h1><p className="text-muted-foreground">Your patient-facing longitudinal medical record.</p></div><div className="card-medical p-5"><p className="text-xs uppercase text-muted-foreground">Patient</p><h2 className="text-xl font-semibold">{snapshot?.patient?.first_name} {snapshot?.patient?.last_name}</h2><p className="text-sm text-muted-foreground">{snapshot?.patient?.patient_code}</p></div><div className="grid gap-6">{sections.map(([title,value,render]:any)=><section key={title} className="card-medical p-5"><div className="flex items-center justify-between mb-3"><h2 className="font-semibold">{title}</h2><span className="text-xs rounded-full border px-2.5 py-1">{rows(value).length}</span></div>{rows(value).length?<div className="space-y-2">{rows(value).map((item:any,i:number)=><article key={item.id??i} className="rounded-xl border border-border p-3 text-sm">{render(item)}</article>)}</div>:<p className="text-sm text-muted-foreground">No records available.</p>}</section>)}</div></div>;
}

export default function MedicalRecords(){const {user}=useAuth(); return user?.roles?.includes('patient')?<PatientMedicalRecords/>:<StaffMedicalRecords/>;}
