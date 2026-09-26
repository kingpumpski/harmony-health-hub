import { getOperationalWorkspace } from '@/lib/operationalWorkspace';
import { searchPatientDirectory } from '@/lib/patientDirectory';
import { useEffect, useState } from 'react';
import { ClipboardCheck, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';
import { toast } from '@/hooks/use-toast';

type Patient={id:string;patient_code:string;first_name:string;last_name:string};
type Handover={id:string;patient_id:string;shift_label:string;clinical_summary:string;pending_tasks:string|null;safety_concerns:string|null;escalation_required:boolean;acknowledged_at:string|null;created_at:string};
export default function NursingHandover(){const{user}=useAuth();const[patients,setPatients]=useState<Patient[]>([]);const[rows,setRows]=useState<Handover[]>([]);const[patientId,setPatientId]=useState('');const[form,setForm]=useState({shift_label:'Morning',clinical_summary:'',pending_tasks:'',safety_concerns:'',escalation_required:false});
const load=async()=>{const[p,h]=await Promise.all([searchPatientDirectory('', 300),(async()=>{const{data,error}=await getOperationalWorkspace('handover', 50);return{data:(data as any)?.handovers??[],error}})()]);if(p.error||h.error)toast({title:'Unable to load handovers',description:(p.error||h.error)?.message,variant:'destructive'});setPatients((p.data??[])as Patient[]);setRows((h.data??[])as Handover[])};useEffect(()=>{void load()},[]);
const save=async()=>{if(!patientId||!form.clinical_summary.trim()){toast({title:'Complete the handover summary',variant:'destructive'});return}const{error}=await supabase.rpc('create_nursing_shift_handover',{_patient_id:patientId,_shift_label:form.shift_label,_clinical_summary:form.clinical_summary,_pending_tasks:form.pending_tasks||null,_safety_concerns:form.safety_concerns||null,_escalation_required:form.escalation_required}as never);if(error)toast({title:'Handover failed',description:error.message,variant:'destructive'});else{toast({title:'Handover recorded'});setPatientId('');setForm({shift_label:'Morning',clinical_summary:'',pending_tasks:'',safety_concerns:'',escalation_required:false});void load()}};
const ack=async(id:string)=>{const{error}=await supabase.rpc('acknowledge_nursing_handover',{_handover_id:id}as never);if(error)toast({title:'Acknowledgement failed',description:error.message,variant:'destructive'});else{toast({title:'Handover acknowledged'});void load()}};const name=(id:string)=>{const p=patients.find(x=>x.id===id);return p?`${p.patient_code} — ${p.first_name} ${p.last_name}`:'Patient'};
return (
  <OperationalWorklistShell
    icon={ClipboardCheck}
    eyebrow="Nursing services"
    title="Nursing Shift Handover"
    description="Structured continuity, pending tasks and safety escalation."
    actions={<button type="button" onClick={() => void load()} className="btn-secondary inline-flex items-center gap-2"><RefreshCw className="h-4 w-4" /> Refresh</button>}
    counters={[
      { label: "Handover records", value: rows.length, tone: "text-primary", surface: "bg-primary/5" },
      { label: "Unacknowledged", value: rows.filter((r) => !r.acknowledged_at).length, tone: "text-warning", surface: "bg-warning/5" },
      { label: "Escalations", value: rows.filter((r) => r.escalation_required).length, tone: "text-critical", surface: "bg-critical/5" },
      { label: "Acknowledged", value: rows.filter((r) => !!r.acknowledged_at).length, tone: "text-success", surface: "bg-success/5" },
    ]}
    beforeList={
      <section className="card-medical p-5 sm:p-6 space-y-4" aria-labelledby="handover-form-heading">
        <div><h2 id="handover-form-heading" className="font-semibold">Record handover</h2><p className="text-xs text-muted-foreground">Capture the patient context and outstanding safety or continuity actions.</p></div>
        <label className="block space-y-1.5 text-sm"><span className="font-medium">Patient</span><select required aria-label="Patient for handover" value={patientId} onChange={e=>setPatientId(e.target.value)} className="input-medical w-full"><option value="">Select patient</option>{patients.map(p=><option key={p.id} value={p.id}>{name(p.id)}</option>)}</select></label>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <label className="space-y-1.5 text-sm"><span className="font-medium">Shift</span><select aria-label="Handover shift" value={form.shift_label} onChange={e=>setForm({...form,shift_label:e.target.value})} className="input-medical w-full"><option>Morning</option><option>Afternoon</option><option>Night</option></select></label>
          <label className="flex items-center gap-2 rounded-xl border border-border px-3 py-2 text-sm"><input type="checkbox" checked={form.escalation_required} onChange={e=>setForm({...form,escalation_required:e.target.checked})}/> Escalation required</label>
        </div>
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <label className="space-y-1.5 text-sm"><span className="font-medium">Clinical summary</span><textarea required aria-label="Clinical summary" placeholder="Clinical summary" value={form.clinical_summary} onChange={e=>setForm({...form,clinical_summary:e.target.value})} className="input-medical min-h-28 w-full"/></label>
          <label className="space-y-1.5 text-sm"><span className="font-medium">Pending tasks</span><textarea aria-label="Pending tasks" placeholder="Pending tasks" value={form.pending_tasks} onChange={e=>setForm({...form,pending_tasks:e.target.value})} className="input-medical min-h-28 w-full"/></label>
          <label className="space-y-1.5 text-sm"><span className="font-medium">Safety concerns</span><textarea aria-label="Safety concerns" placeholder="Safety concerns" value={form.safety_concerns} onChange={e=>setForm({...form,safety_concerns:e.target.value})} className="input-medical min-h-28 w-full"/></label>
        </div>
        <button type="button" onClick={()=>void save()} className="btn-primary inline-flex items-center gap-2"><ClipboardCheck className="h-4 w-4"/>Record handover</button>
      </section>
    }
    listTitle="Handover worklist"
    listDescription="Review continuity information and acknowledge handovers requiring follow-through."
    listMeta={`${rows.length} record${rows.length === 1 ? '' : 's'}`}
    empty={!rows.length}
    emptyTitle="No handover records found"
    emptyDescription="Record the first shift handover above to begin continuity tracking."
  >
    {rows.map(r=><article key={r.id} className="px-5 py-4 transition-colors hover:bg-muted/30">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0">
          <p className="font-medium">{name(r.patient_id)} · {r.shift_label}</p>
          <p className="mt-1 text-sm whitespace-pre-wrap">{r.clinical_summary}</p>
          <div className="mt-2 flex flex-wrap gap-2 text-xs text-muted-foreground">
            <span className={`rounded-full px-2 py-1 ${r.acknowledged_at ? 'bg-success/10 text-success' : 'bg-warning/10 text-warning'}`}>{r.acknowledged_at ? 'Acknowledged' : 'Awaiting acknowledgement'}</span>
            {r.escalation_required && <span className="rounded-full bg-critical/10 px-2 py-1 text-critical">Escalation required</span>}
          </div>
          {r.pending_tasks&&<p className="mt-3 text-xs"><span className="font-medium">Tasks:</span> {r.pending_tasks}</p>}
          {r.safety_concerns&&<p className="mt-1 text-xs"><span className="font-medium">Safety:</span> {r.safety_concerns}</p>}
        </div>
        {!r.acknowledged_at && <button type="button" onClick={()=>void ack(r.id)} className="btn-secondary text-sm">Acknowledge</button>}
      </div>
    </article>)}
  </OperationalWorklistShell>
);
}
