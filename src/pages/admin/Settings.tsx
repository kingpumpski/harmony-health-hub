import { useEffect, useState } from 'react';
import { Building2, Save, Settings as SettingsIcon, ShieldAlert } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

type Config = {
 id:string; facility_name:string; facility_code:string|null; phone:string|null; email:string|null;
 address:string|null; country:string; currency:string; timezone:string; routing_mode:string;
 appointment_buffer_minutes:number; maintenance_mode:boolean; allow_treatment_before_deposit:boolean;
 admission_financial_override_enabled:boolean; require_accounts_release_after_deposit:boolean;
 allow_clinical_emergency_override:boolean;
};
const db = supabase as any;
const fields = ['facility_name','facility_code','phone','email','country','currency','timezone'] as const;

export default function Settings(){
 const [config,setConfig]=useState<Config|null>(null); const [loading,setLoading]=useState(true); const [saving,setSaving]=useState(false);
 useEffect(()=>{void load()},[]);
 async function load(){setLoading(true);const {data,error}=await db.from('facility_configuration').select('id,facility_name,facility_code,phone,email,address,country,currency,timezone,routing_mode,appointment_buffer_minutes,maintenance_mode,allow_treatment_before_deposit,admission_financial_override_enabled,require_accounts_release_after_deposit,allow_clinical_emergency_override').limit(1).maybeSingle();if(error)toast.error(error.message);setConfig(data as Config|null);setLoading(false)}
 async function save(){if(!config)return;setSaving(true);const user=(await supabase.auth.getUser()).data.user;const {error}=await db.from('facility_configuration').update({...config,updated_by:user?.id??null}).eq('id',config.id);if(error)toast.error(error.message);else toast.success('Facility configuration saved.');setSaving(false)}
 if(loading)return <div className="p-6 text-sm text-muted-foreground">Loading facility configuration…</div>;
 if(!config)return <div className="card-medical p-6 text-sm text-muted-foreground">No facility configuration is available. Apply the approved configuration migration before using this page.</div>;
 return <div className="space-y-6 animate-fade-in">
  <header><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><SettingsIcon className="w-6 h-6 text-primary"/>System Settings</h1><p className="text-muted-foreground">Facility-wide controls for clinical routing, emergency treatment and financial workflow.</p></header>
  <section className="card-medical rounded-3xl p-5 space-y-5">
   <div className="grid gap-4 md:grid-cols-2">{fields.map(key=><label key={key} className="text-sm space-y-1 block"><span className="capitalize">{key.replaceAll('_',' ')}</span><input className="input-medical w-full" value={config[key]??''} onChange={e=>setConfig({...config,[key]:e.target.value})}/></label>)}
    <label className="text-sm space-y-1 block"><span>Appointment buffer (minutes)</span><input type="number" min="0" className="input-medical w-full" value={config.appointment_buffer_minutes} onChange={e=>setConfig({...config,appointment_buffer_minutes:Math.max(0,Number(e.target.value))})}/></label>
    <label className="text-sm space-y-1 block"><span>Clinical routing</span><select className="input-medical w-full" value={config.routing_mode} onChange={e=>setConfig({...config,routing_mode:e.target.value})}><option value="streamlined">Streamlined</option><option value="pay_before_each_step">Pay before each step</option></select></label>
   </div>
   <label className="text-sm block space-y-1"><span>Address</span><textarea className="input-medical w-full" value={config.address??''} onChange={e=>setConfig({...config,address:e.target.value})}/></label>
   <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={config.maintenance_mode} onChange={e=>setConfig({...config,maintenance_mode:e.target.checked})}/>Maintenance mode</label>
   <section className="rounded-2xl border border-warning/30 bg-warning/5 p-4 space-y-4">
    <div className="flex gap-3"><ShieldAlert className="w-5 h-5 text-warning"/><div><h2 className="font-semibold">Emergency treatment & financial override</h2><p className="text-xs text-muted-foreground">These settings control whether clinically necessary treatment can continue while Accounts completes deposit and financial clearance.</p></div></div>
    <Toggle label="Allow treatment before deposit" checked={config.allow_treatment_before_deposit} onChange={v=>setConfig({...config,allow_treatment_before_deposit:v})}/>
    <Toggle label="Allow admission financial override" checked={config.admission_financial_override_enabled} onChange={v=>setConfig({...config,admission_financial_override_enabled:v})}/>
    <Toggle label="Allow clinical emergency override" checked={config.allow_clinical_emergency_override} onChange={v=>setConfig({...config,allow_clinical_emergency_override:v})}/>
    <Toggle label="Require Accounts release after deposit" checked={config.require_accounts_release_after_deposit} onChange={v=>setConfig({...config,require_accounts_release_after_deposit:v})}/>
   </section>
   <button disabled={saving} onClick={()=>void save()} className="btn-primary inline-flex items-center gap-2"><Save className="w-4 h-4"/>{saving?'Saving…':'Save configuration'}</button>
  </section>
  <section className="card-medical p-5"><div className="flex gap-3"><Building2 className="w-5 h-5 text-primary"/><div><h2 className="font-semibold">Operational configuration</h2><p className="text-sm text-muted-foreground mt-1">Service tariffs, laboratory catalogues and staff profile administration remain in their dedicated administrative modules. This page is intentionally focused on facility-level controls.</p></div></div></section>
 </div>
}
function Toggle({label,checked,onChange}:{label:string;checked:boolean;onChange:(value:boolean)=>void}){return <label className="flex items-start gap-3 text-sm"><input type="checkbox" className="mt-1" checked={checked} onChange={e=>onChange(e.target.checked)}/><span><b>{label}</b><br/><small className="text-muted-foreground">Facility administrator controlled.</small></span></label>}
