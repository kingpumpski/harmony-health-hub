import { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowLeft, BedDouble, ChevronRight, Loader2, RefreshCw, Search, WalletCards } from 'lucide-react';
import { useNavigate, useParams } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';

const db=supabase as any;
const money=(v:number)=>`₵${Number(v||0).toFixed(2)}`;
const categories=['Consultation','Laboratory','Radiology','Drugs/Medications','Accommodation','Nursing Care','Consumables','Feeding','Other Services'];
const categoryFor=(item:any)=>{
 const s=`${item.category||''} ${item.department||''} ${item.description||''}`.toLowerCase();
 if(s.includes('consult')) return 'Consultation';
 if(s.includes('lab')) return 'Laboratory';
 if(s.includes('radi')||s.includes('imag')) return 'Radiology';
 if(s.includes('pharm')||s.includes('drug')||s.includes('med')) return 'Drugs/Medications';
 if(s.includes('ward')||s.includes('accommod')) return 'Accommodation';
 if(s.includes('nurs')) return 'Nursing Care';
 if(s.includes('consum')) return 'Consumables';
 if(s.includes('feed')||s.includes('diet')) return 'Feeding';
 return 'Other Services';
};

export default function InpatientBilling(){
 const navigate=useNavigate(); const {patientId}=useParams<{patientId?:string}>(); const {user}=useAuth();
 const [patients,setPatients]=useState<any[]>([]); const [rows,setRows]=useState<any[]>([]); const [selected,setSelected]=useState(patientId||''); const [search,setSearch]=useState(''); const [loading,setLoading]=useState(true); const [admission,setAdmission]=useState<any>(null);
 const load=useCallback(async()=>{
  setLoading(true);
  const {data:ad,error}=await db.rpc('get_admission_workspace',{_limit:500});
  if(error){setLoading(false);toast.error(error.message);return;}
  const admissions=Array.isArray(ad)?ad:(ad?.admissions??[]);
  const active=admissions.filter((a:any)=>a.status==='admitted'&&!a.discharged_at);
  const ids=active.map((a:any)=>a.patient_id);
  if(!ids.length){setPatients([]);setRows([]);setLoading(false);return;}
  const {data:dir,error:pe}=await db.rpc('get_patient_directory',{_limit:1000});
  if(pe){setLoading(false);toast.error(pe.message);return;}
  const map=(dir??[]).filter((p:any)=>ids.includes(p.id)); setPatients(map);
  if(selected){
   const selectedAdmission=active.find((a:any)=>a.patient_id===selected); setAdmission(selectedAdmission??null);
   if(selectedAdmission){
    const from=new Date(selectedAdmission.admitted_at).toISOString(); const to=new Date().toISOString();
    const {data:items,error:be}=await db.rpc('prepare_patient_billable_items',{_patient_id:selected,_from:from,_to:to});
    if(be) toast.error(be.message); else setRows(items??[]);
   }
  } else { setRows([]); setAdmission(null); }
  setLoading(false);
 },[selected]);
 useEffect(()=>{void load()},[load]);
 useEffect(()=>{if(patientId && patientId!==selected) setSelected(patientId)},[patientId,selected]);
 const selectedPatient=patients.find(p=>p.id===selected);
 const filtered=patients.filter(p=>`${p.first_name} ${p.last_name} ${p.patient_code}`.toLowerCase().includes(search.toLowerCase()));
 const grouped=useMemo(()=>categories.map(category=>({category,items:rows.filter(r=>categoryFor(r)===category)})).filter(g=>g.items.length),[rows]);
 const total=rows.reduce((sum,r)=>sum+Number(r.outstanding_amount??r.amount??0),0);

 return <div className="space-y-6 animate-fade-in">
  <header className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between"><div><div className="flex items-center gap-2 text-primary"><BedDouble className="h-6 w-6"/><span className="text-xs uppercase tracking-wide font-semibold">Billing · Inpatient</span></div><h1 className="mt-1 text-2xl font-heading font-bold">Inpatient Discharge Billing</h1><p className="text-sm text-muted-foreground">Reconcile all billable services from admission through the current discharge point. Unpaid items remain attached to the account.</p></div><div className="flex gap-2"><button className="btn-secondary inline-flex items-center gap-2" onClick={()=>navigate('/billing')}><ArrowLeft className="h-4 w-4"/> Billing</button><button aria-label="Refresh inpatient billing" title="Refresh" className="btn-secondary" onClick={()=>void load()} disabled={loading}><RefreshCw className={`h-4 w-4 ${loading?'animate-spin':''}`}/></button></div></header>
  <div className="grid gap-6 lg:grid-cols-[320px_1fr]">
   <section className="card-medical p-4"><div className="relative mb-3"><Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground"/><input value={search} onChange={e=>setSearch(e.target.value)} className="input-medical w-full pl-9" placeholder="Search active inpatient…"/></div><div className="space-y-1">{filtered.map(p=><button key={p.id} onClick={()=>navigate(`/billing/inpatients/${p.id}`)} className={`w-full text-left rounded-xl p-3 flex items-center justify-between ${selected===p.id?'bg-primary/10 border border-primary/20':'hover:bg-muted'}`}><span><span className="font-medium">{p.first_name} {p.last_name}</span><span className="block text-xs text-muted-foreground">{p.patient_code}</span></span><ChevronRight className="h-4 w-4"/></button>)}{!filtered.length&&<p className="p-4 text-sm text-muted-foreground">No active inpatients.</p>}</div></section>
   <section className="space-y-4">
    {selectedPatient ? <><div className="card-medical p-5 flex flex-wrap items-center justify-between gap-4"><div><p className="text-xs uppercase tracking-wide text-primary font-semibold">Discharge account</p><h2 className="text-xl font-semibold">{selectedPatient.first_name} {selectedPatient.last_name}</h2><p className="text-sm text-muted-foreground">{selectedPatient.patient_code} · Admitted {admission ? new Date(admission.admitted_at).toLocaleString() : '—'}</p></div><div className="text-right"><p className="text-xs text-muted-foreground">Outstanding</p><p className="text-2xl font-bold text-warning">{money(total)}</p></div></div>
    {loading?<div className="card-medical p-10 text-center"><Loader2 className="mx-auto h-6 w-6 animate-spin"/></div>:grouped.length?grouped.map(g=><section key={g.category} className="card-medical overflow-hidden"><div className="border-b p-4 flex justify-between"><h3 className="font-semibold">{g.category}</h3><span className="font-semibold">{money(g.items.reduce((s:number,r:any)=>s+Number(r.outstanding_amount??r.amount??0),0))}</span></div><div className="divide-y">{g.items.map((r:any)=><div key={r.invoice_item_id} className="p-4 flex justify-between gap-4"><div><p className="font-medium">{r.description}</p><p className="text-xs text-muted-foreground">{r.quantity} × {money(r.unit_price)} · {r.service_order_status||'recorded'}</p></div><span className="font-medium">{money(Number(r.outstanding_amount??r.amount??0))}</span></div>)}</div></section>):<div className="card-medical p-10 text-center text-muted-foreground">No billable services have been recorded for this active admission yet.</div>}
    <div className="card-medical p-5 flex items-center justify-between"><span className="font-semibold">Grand Total Outstanding</span><span className="text-2xl font-bold">{money(total)}</span></div>
    </>:<div className="card-medical p-12 text-center"><WalletCards className="mx-auto h-10 w-10 text-primary/60"/><h2 className="mt-3 font-semibold">Select an active inpatient</h2><p className="mt-1 text-sm text-muted-foreground">Choose a patient to prepare the discharge account.</p></div>}
   </section>
  </div>
 </div>;
}
