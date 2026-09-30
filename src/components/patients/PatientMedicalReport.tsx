import { useMemo, useState } from 'react';
import { FileText, Printer, X } from 'lucide-react';

type Props = {
  patient: any;
  rows: Record<string, any[]>;
  onClose: () => void;
};

const sections = [
  ['profile','Patient profile'],['vitals','Vitals / triage'],['encounters','Encounters'],['labs','Laboratory'],['prescriptions','Prescriptions'],['billing','Billing'],['documents','Documents']
] as const;

function fmt(value:any){return value ? new Date(value).toLocaleString([], {dateStyle:'medium',timeStyle:'short'}) : '—';}

export default function PatientMedicalReport({patient,rows,onClose}:Props){
 const encounters=useMemo(()=>rows.encounters??[],[rows.encounters]);
 const [selectedEncounters,setSelectedEncounters]=useState<string[]>(encounters.map((e:any)=>e.id));
 const [selectedSections,setSelectedSections]=useState<string[]>(sections.map(([key])=>key));
 const [title,setTitle]=useState('Medical Report');
 const selected=useMemo(()=>encounters.filter((e:any)=>selectedEncounters.includes(e.id)),[encounters,selectedEncounters]);
 const toggle=(list:string[],value:string)=>list.includes(value)?list.filter((x)=>x!==value):[...list,value];
 return <div className="fixed inset-0 z-[80] flex items-center justify-center bg-slate-950/50 p-4" role="dialog" aria-modal="true" aria-labelledby="medical-report-title">
  <div className="max-h-[92vh] w-full max-w-5xl overflow-hidden rounded-3xl border border-border bg-card shadow-elevated">
   <header className="flex items-start justify-between gap-4 border-b p-5"><div><p className="text-xs font-semibold uppercase tracking-wider text-primary">Patient Hub · Report Composer</p><h2 id="medical-report-title" className="mt-1 text-xl font-bold">Generate medical report</h2><p className="text-sm text-muted-foreground">{patient.first_name} {patient.last_name} · {patient.patient_code}</p></div><button className="btn-ghost p-2" onClick={onClose} aria-label="Close report composer"><X className="h-5 w-5"/></button></header>
   <div className="grid max-h-[78vh] overflow-auto lg:grid-cols-[18rem_1fr]">
    <aside className="border-b border-border p-5 lg:border-b-0 lg:border-r"><label className="text-sm font-medium">Report title<input className="input-medical mt-1 w-full" value={title} onChange={e=>setTitle(e.target.value)}/></label><div className="mt-5"><p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Include sections</p><div className="mt-2 space-y-2">{sections.map(([key,label])=><label key={key} className="flex items-center gap-2 text-sm"><input type="checkbox" checked={selectedSections.includes(key)} onChange={()=>setSelectedSections(toggle(selectedSections,key))}/>{label}</label>)}</div></div><div className="mt-5"><p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Encounters</p><div className="mt-2 max-h-56 space-y-2 overflow-auto">{encounters.map((enc:any)=><label key={enc.id} className="flex items-start gap-2 text-sm"><input type="checkbox" checked={selectedEncounters.includes(enc.id)} onChange={()=>setSelectedEncounters(toggle(selectedEncounters,enc.id))}/><span>{fmt(enc.created_at)}<span className="block text-xs text-muted-foreground">{enc.principal_diagnosis||enc.status||'Encounter'}</span></span></label>)}{!encounters.length&&<p className="text-xs text-muted-foreground">No encounter records are available.</p>}</div></div></aside>
    <article className="bg-background p-6 print:bg-white" id="patient-medical-report"><div className="flex items-start justify-between gap-4"><div><h1 className="text-2xl font-heading font-bold">{title||'Medical Report'}</h1><p className="mt-1 text-sm text-muted-foreground">{patient.first_name} {patient.last_name} · {patient.patient_code} · Generated {new Date().toLocaleString()}</p></div><FileText className="h-6 w-6 text-primary"/></div>
      {selectedSections.includes('profile')&&<section className="mt-6"><h3 className="font-semibold">Patient profile</h3><div className="mt-2 grid gap-2 text-sm sm:grid-cols-2"><p><b>Date of birth:</b> {patient.date_of_birth||'—'}</p><p><b>Gender:</b> {patient.gender||'—'}</p><p><b>Phone:</b> {patient.phone||'—'}</p><p><b>Blood group:</b> {patient.blood_group||'—'}</p><p className="sm:col-span-2"><b>Allergies:</b> {patient.allergies||'—'}</p></div></section>}
      {selectedSections.includes('encounters')&&<section className="mt-6"><h3 className="font-semibold">Selected encounters</h3><div className="mt-2 space-y-2">{selected.map((e:any)=><div key={e.id} className="rounded-xl border p-3 text-sm"><p className="font-medium">{fmt(e.created_at)} · {e.status||'Encounter'}</p><p className="text-muted-foreground">{e.principal_diagnosis||'No principal diagnosis recorded.'}</p></div>)}</div></section>}
      {selectedSections.includes('vitals')&&<section className="mt-6"><h3 className="font-semibold">Vitals / triage</h3><div className="mt-2 overflow-x-auto"><table className="w-full text-sm"><tbody>{(rows.vitals??[]).slice(0,50).map((v:any)=><tr key={v.id||v.created_at} className="border-b"><td className="p-2">{fmt(v.created_at||v.recorded_at)}</td><td className="p-2">{v.temperature??'—'}</td><td className="p-2">{v.systolic_bp??'—'}/{v.diastolic_bp??'—'}</td><td className="p-2">{v.pulse??'—'}</td><td className="p-2">{v.spo2??'—'}</td><td className="p-2">{v.bmi??'—'}</td></tr>)}</tbody></table></div></section>}
      {selectedSections.includes('labs')&&<section className="mt-6"><h3 className="font-semibold">Laboratory results</h3><div className="mt-2 space-y-2">{(rows.labs??[]).map((l:any)=><div key={l.id} className="rounded-xl border p-3 text-sm"><div className="flex justify-between gap-3"><b>{l.test_name||l.test||'Laboratory test'}</b><span>{l.status||'—'}</span></div><p className="text-muted-foreground">{l.result||l.result_text||l.interpretation||'Result not recorded.'}</p></div>)}</div></section>}
      {selectedSections.includes('prescriptions')&&<section className="mt-6"><h3 className="font-semibold">Prescriptions</h3><div className="mt-2 space-y-2">{(rows.prescriptions??[]).map((p:any)=><div key={p.id} className="rounded-xl border p-3 text-sm"><b>{p.medication_name||p.name||'Medication'}</b><p className="text-muted-foreground">{p.dosage||p.instructions||'—'}</p></div>)}</div></section>}
      {selectedSections.includes('billing')&&<section className="mt-6"><h3 className="font-semibold">Billing summary</h3><p className="mt-2 text-sm text-muted-foreground">{(rows.invoices??[]).length} invoice record(s) included.</p></section>}
      {selectedSections.includes('documents')&&<section className="mt-6"><h3 className="font-semibold">Documents</h3><div className="mt-2 space-y-2">{(rows.documents??[]).map((d:any)=><div key={d.id} className="rounded-xl border p-3 text-sm"><b>{d.document_type||'Document'}</b><p className="text-muted-foreground">{d.notes||'—'}</p></div>)}</div></section>}
    </article>
   </div>
   <footer className="flex justify-end gap-2 border-t p-4"><button className="btn-secondary" onClick={onClose}>Cancel</button><button className="btn-primary inline-flex items-center gap-2" onClick={()=>window.print()}><Printer className="h-4 w-4"/>Print / Save PDF</button></footer>
  </div>
 </div>;
}
