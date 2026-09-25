import { useEffect, useMemo, useState } from 'react';
import { Bell, Building2, Save, Settings as SettingsIcon, ShieldAlert, Wrench } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import {
  configureFacilityNotificationProvider,
  getFacilityNotificationConfig,
  initializeFacilityNotificationOnboarding,
  listFacilities,
  listNotificationProviderSecretRequirements,
  type FacilityNotificationConfig,
  type HealthcareFacility,
  type NotificationProviderSecretRequirement,
} from '@/lib/reportsCenter';

type Config = {
 id:string; facility_name:string; facility_code:string|null; phone:string|null; email:string|null;
 address:string|null; country:string; currency:string; timezone:string; routing_mode:string;
 appointment_buffer_minutes:number; maintenance_mode:boolean; allow_treatment_before_deposit:boolean;
 admission_financial_override_enabled:boolean; require_accounts_release_after_deposit:boolean;
 allow_clinical_emergency_override:boolean; require_principal_diagnosis_for_final:boolean; inherit_inpatient_diagnoses:boolean; notification_sound_enabled:boolean;
};

type ProviderConnection = {
 id:string; facility_id:string; channel:string; provider:string; environment:string; secret_reference:string|null;
 sender_identity:string|null; account_reference:string|null; status:string; last_verified_at:string|null; last_error:string|null;
};

const db = supabase as any;
const fields = ['facility_name','facility_code','phone','email','country','currency','timezone'] as const;
const channels = [
  { code:'email', label:'Email', defaultProvider:'resend' },
  { code:'sms', label:'SMS', defaultProvider:'twilio' },
  { code:'push', label:'Push', defaultProvider:'fcm' },
  { code:'whatsapp', label:'WhatsApp', defaultProvider:'twilio_whatsapp' },
  { code:'voice', label:'Voice', defaultProvider:'twilio_voice' },
] as const;

export default function Settings(){
 const { user } = useAuth();
 const canConfigure = user?.role === 'admin' || user?.role === 'it_admin';
 const [config,setConfig]=useState<Config|null>(null);
 const [loading,setLoading]=useState(true);
 const [saving,setSaving]=useState(false);
 const [facilities,setFacilities]=useState<HealthcareFacility[]>([]);
 const [facilityId,setFacilityId]=useState('');
 const [notification,setNotification]=useState<FacilityNotificationConfig|null>(null);
 const [providerConnections,setProviderConnections]=useState<ProviderConnection[]>([]);
 const [secretRequirements,setSecretRequirements]=useState<NotificationProviderSecretRequirement[]>([]);
 const [notificationLoading,setNotificationLoading]=useState(false);
 const [notificationSaving,setNotificationSaving]=useState(false);
 const [providerDraft,setProviderDraft]=useState({channel:'email',provider:'resend',environment:'sandbox',secretReference:'',senderIdentity:'',accountReference:''});
 useMemo(()=>facilities.find(f=>f.id===facilityId) ?? null,[facilities,facilityId]);

 useEffect(()=>{void load()},[]);
 async function load(){
   setLoading(true);
   const [{data,error}, facilityResult] = await Promise.all([
     db.from('facility_configuration').select('id,facility_name,facility_code,phone,email,address,country,currency,timezone,routing_mode,appointment_buffer_minutes,maintenance_mode,allow_treatment_before_deposit,admission_financial_override_enabled,require_accounts_release_after_deposit,allow_clinical_emergency_override,require_principal_diagnosis_for_final,inherit_inpatient_diagnoses,notification_sound_enabled').limit(1).maybeSingle(),
     listFacilities().catch(()=>[]),
   ]);
   if(error) toast.error(error.message);
   setConfig(data as Config|null);
   setFacilities(facilityResult);
   const initial = facilityResult[0]?.id ?? '';
   setFacilityId(initial);
   setLoading(false);
   if(initial) void loadNotificationSettings(initial);
 }
 async function loadNotificationSettings(id:string){
   setNotificationLoading(true);
   try {
     const [cfg, requirements, connections] = await Promise.all([
       getFacilityNotificationConfig(id),
       listNotificationProviderSecretRequirements(),
       db.from('facility_notification_provider_connections').select('id,facility_id,channel,provider,environment,secret_reference,sender_identity,account_reference,status,last_verified_at,last_error').eq('facility_id',id).order('channel').order('environment'),
     ]);
     setNotification(cfg);
     setSecretRequirements(requirements);
     if(connections.error) throw new Error(connections.error.message);
     setProviderConnections((connections.data ?? []) as ProviderConnection[]);
     if(!cfg){
       const initialized = await initializeFacilityNotificationOnboarding(id);
       setNotification(initialized);
     }
   } catch(error) {
     toast.error(error instanceof Error ? error.message : 'Unable to load notification settings.');
   } finally { setNotificationLoading(false); }
 }
 async function save(){
   if(!config)return;
   setSaving(true);
   const changes={...config};
   delete (changes as any).id;
   const {error}=await db.rpc('update_facility_configuration_workflow',{_configuration_id:config.id,_changes:changes});
   if(error)toast.error(error.message);else toast.success('Facility configuration saved.');
   setSaving(false);
 }
 async function saveNotification(){
   if(!notification || !facilityId) return;
   setNotificationSaving(true);
   try {
     const {data,error}=await db.rpc('update_facility_notification_configuration',{_facility_id:facilityId,_changes:{
       environment:notification.environment, enabled:notification.enabled, default_locale:notification.default_locale,
       default_timezone:notification.default_timezone, quiet_hours_start:notification.quiet_hours_start,
       quiet_hours_end:notification.quiet_hours_end, enabled_channels:notification.enabled_channels,
       branding:notification.branding, provider_defaults:notification.provider_defaults,
       delivery_policy:notification.delivery_policy, webhook_policy:notification.webhook_policy,
       compliance_policy:notification.compliance_policy, operational_contacts:notification.operational_contacts,
       deployment_secret_namespace:notification.deployment_secret_namespace,
       rollout_percent:notification.rollout_percent, kill_switch:notification.kill_switch,
     }});
     if(error) throw new Error(error.message);
     setNotification(data as FacilityNotificationConfig);
     toast.success('Notification control-plane settings saved.');
   } catch(error) { toast.error(error instanceof Error ? error.message : 'Unable to save notification settings.'); }
   finally { setNotificationSaving(false); }
 }
 async function saveProvider(){
   if(!facilityId)return;
   try {
     await configureFacilityNotificationProvider({
       facilityId, channel:providerDraft.channel as any, provider:providerDraft.provider,
       environment:providerDraft.environment as any, secretReference:providerDraft.secretReference || null,
       senderIdentity:providerDraft.senderIdentity || null, accountReference:providerDraft.accountReference || null,
     });
     toast.success('Provider configuration saved. Credentials remain outside PostgreSQL.');
     await loadNotificationSettings(facilityId);
   } catch(error) { toast.error(error instanceof Error ? error.message : 'Unable to save provider configuration.'); }
 }
 function toggleChannel(code:string,value:boolean){
   if(!notification)return;
   setNotification({...notification,enabled_channels:{...notification.enabled_channels,[code]:value}});
 }
 if(!canConfigure)return <div className="p-6 text-sm text-muted-foreground">System Settings are restricted to administrators and IT administrators.</div>;
 if(loading)return <div className="p-6 text-sm text-muted-foreground">Loading facility configuration…</div>;
 if(!config)return <div className="card-medical p-6 text-sm text-muted-foreground">No facility configuration is available. Apply the approved configuration migration before using this page.</div>;

 return <div className="space-y-6 animate-fade-in">
  <header>
   <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><SettingsIcon className="w-6 h-6 text-primary"/>System Settings</h1>
   <p className="text-muted-foreground">Central configuration and operational control plane for administrators and IT administrators.</p>
  </header>

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
   <section className="rounded-2xl border border-primary/30 bg-primary/5 p-4 space-y-4">
    <div><h2 className="font-semibold">Clinical encounter continuity</h2><p className="text-xs text-muted-foreground mt-1">Facility-level rules for draft-first documentation, principal diagnosis reporting and inpatient continuity.</p></div>
    <Toggle label="Require principal diagnosis before final submission" checked={config.require_principal_diagnosis_for_final} onChange={v=>setConfig({...config,require_principal_diagnosis_for_final:v})}/>
    <Toggle label="Inherit diagnoses into subsequent inpatient encounters" checked={config.inherit_inpatient_diagnoses} onChange={v=>setConfig({...config,inherit_inpatient_diagnoses:v})}/>
    <Toggle label="Enable workflow notification sounds" checked={config.notification_sound_enabled} onChange={v=>setConfig({...config,notification_sound_enabled:v})}/>
   </section>
   <button disabled={saving} onClick={()=>void save()} className="btn-primary inline-flex items-center gap-2"><Save className="w-4 h-4"/>{saving?'Saving…':'Save facility configuration'}</button>
  </section>

  <section className="card-medical rounded-3xl p-5 space-y-5">
   <div className="flex gap-3"><Bell className="w-5 h-5 text-primary mt-1"/><div><h2 className="font-semibold">Notification Control Plane</h2><p className="text-sm text-muted-foreground">Configure notification behavior, providers, rollout and troubleshooting controls. Secret values are never stored here.</p></div></div>
   <label className="text-sm space-y-1 block"><span>Facility</span><select className="input-medical w-full" value={facilityId} onChange={e=>{setFacilityId(e.target.value);void loadNotificationSettings(e.target.value)}}>{facilities.map(f=><option key={f.id} value={f.id}>{f.name}{f.facility_code ? ' (' + f.facility_code + ')' : ''}</option>)}</select></label>
   {notificationLoading ? <div className="text-sm text-muted-foreground">Loading notification configuration…</div> : notification ? <>
    <div className="grid gap-4 md:grid-cols-3">
     <label className="text-sm space-y-1"><span>Environment</span><select className="input-medical w-full" value={notification.environment} onChange={e=>setNotification({...notification,environment:e.target.value as any})}><option value="sandbox">Sandbox</option><option value="test">Test</option><option value="production">Production</option></select></label>
     <label className="text-sm space-y-1"><span>Default locale</span><input className="input-medical w-full" value={notification.default_locale} onChange={e=>setNotification({...notification,default_locale:e.target.value})}/></label>
     <label className="text-sm space-y-1"><span>IANA timezone</span><input className="input-medical w-full" value={notification.default_timezone} onChange={e=>setNotification({...notification,default_timezone:e.target.value})}/></label>
     <label className="text-sm space-y-1"><span>Quiet hours start</span><input type="time" className="input-medical w-full" value={notification.quiet_hours_start} onChange={e=>setNotification({...notification,quiet_hours_start:e.target.value})}/></label>
     <label className="text-sm space-y-1"><span>Quiet hours end</span><input type="time" className="input-medical w-full" value={notification.quiet_hours_end} onChange={e=>setNotification({...notification,quiet_hours_end:e.target.value})}/></label>
     <label className="text-sm space-y-1"><span>Rollout percentage</span><input type="number" min="0" max="100" className="input-medical w-full" value={notification.rollout_percent} onChange={e=>setNotification({...notification,rollout_percent:Math.max(0,Math.min(100,Number(e.target.value)))})}/></label>
    </div>
    <div className="grid gap-3 md:grid-cols-3">{channels.map(ch=><label key={ch.code} className="rounded-xl border p-3 text-sm flex items-center gap-2"><input type="checkbox" checked={notification.enabled_channels?.[ch.code] === true} onChange={e=>toggleChannel(ch.code,e.target.checked)}/><span>{ch.label}</span></label>)}</div>
    <div className="grid gap-3 md:grid-cols-2">
      <Toggle label="Notification system enabled" checked={notification.enabled} onChange={v=>setNotification({...notification,enabled:v})}/>
      <Toggle label="Global notification kill switch" checked={notification.kill_switch} onChange={v=>setNotification({...notification,kill_switch:v})}/>
    </div>
    <div className="grid gap-4 md:grid-cols-3">
      <label className="text-sm space-y-1"><span>Secret namespace/reference</span><input className="input-medical w-full" placeholder="e.g. org/acme/notifications" value={notification.deployment_secret_namespace ?? ''} onChange={e=>setNotification({...notification,deployment_secret_namespace:e.target.value})}/></label>
      <label className="text-sm space-y-1"><span>Organization display name</span><input className="input-medical w-full" value={String(notification.branding?.display_name ?? '')} onChange={e=>setNotification({...notification,branding:{...notification.branding,display_name:e.target.value}})}/></label>
      <label className="text-sm space-y-1"><span>Reply/contact email</span><input className="input-medical w-full" value={String(notification.branding?.reply_to ?? '')} onChange={e=>setNotification({...notification,branding:{...notification.branding,reply_to:e.target.value}})}/></label>
    </div>
    <div className="rounded-xl border p-4 space-y-3">
      <h3 className="font-semibold flex items-center gap-2"><Wrench className="w-4 h-4"/>Provider configuration</h3>
      <p className="text-xs text-muted-foreground">Store only the secret reference. API keys, passwords, service-account JSON and tokens belong in the approved deployment secret store.</p>
      <div className="grid gap-3 md:grid-cols-3">
       <select className="input-medical" value={providerDraft.channel} onChange={e=>{const ch=channels.find(c=>c.code===e.target.value);setProviderDraft({...providerDraft,channel:e.target.value,provider:ch?.defaultProvider ?? providerDraft.provider})}}>{channels.map(c=><option key={c.code} value={c.code}>{c.label}</option>)}</select>
       <input className="input-medical" placeholder="Provider" value={providerDraft.provider} onChange={e=>setProviderDraft({...providerDraft,provider:e.target.value})}/>
       <select className="input-medical" value={providerDraft.environment} onChange={e=>setProviderDraft({...providerDraft,environment:e.target.value})}><option value="sandbox">Sandbox</option><option value="test">Test</option><option value="production">Production</option></select>
       <input className="input-medical" placeholder="Secret reference only" value={providerDraft.secretReference} onChange={e=>setProviderDraft({...providerDraft,secretReference:e.target.value})}/>
       <input className="input-medical" placeholder="Sender identity" value={providerDraft.senderIdentity} onChange={e=>setProviderDraft({...providerDraft,senderIdentity:e.target.value})}/>
       <input className="input-medical" placeholder="Account/reference" value={providerDraft.accountReference} onChange={e=>setProviderDraft({...providerDraft,accountReference:e.target.value})}/>
      </div>
      <button type="button" onClick={()=>void saveProvider()} className="btn-primary">Save provider metadata</button>
      <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="text-left border-b"><th className="p-2">Channel</th><th className="p-2">Provider</th><th className="p-2">Environment</th><th className="p-2">Status</th><th className="p-2">Last verification</th></tr></thead><tbody>{providerConnections.map(row=><tr key={row.id} className="border-b"><td className="p-2">{row.channel}</td><td className="p-2">{row.provider}</td><td className="p-2">{row.environment}</td><td className="p-2">{row.status}</td><td className="p-2">{row.last_verified_at ? new Date(row.last_verified_at).toLocaleString() : '—'}</td></tr>)}</tbody></table></div>
    </div>
    <div className="rounded-xl border p-4"><h3 className="font-semibold mb-2">Deployment secret checklist</h3><div className="grid gap-2 md:grid-cols-2">{secretRequirements.filter(r=>r.channel==='email' || notification.enabled_channels?.[r.channel]).map(r=><div key={r.id} className="text-xs rounded-lg bg-muted/50 p-2"><b>{r.secret_name}</b> · {r.provider}<br/><span className="text-muted-foreground">{r.description}</span></div>)}</div></div>
    <div className="text-xs text-muted-foreground">Status: <b>{notification.onboarding_status}</b>. Production approval is a separate administrator governance action and requires verified providers for every enabled external channel.</div>
    <button disabled={notificationSaving} onClick={()=>void saveNotification()} className="btn-primary inline-flex items-center gap-2"><Save className="w-4 h-4"/>{notificationSaving?'Saving…':'Save notification settings'}</button>
   </> : <div className="text-sm text-muted-foreground">No notification configuration is available for this facility.</div>}
  </section>

  <section className="card-medical p-5"><div className="flex gap-3"><Building2 className="w-5 h-5 text-primary"/><div><h2 className="font-semibold">Operational configuration</h2><p className="text-sm text-muted-foreground mt-1">Service tariffs, laboratory catalogues, staff administration and deeper troubleshooting remain in their dedicated administrative/IT modules. This page provides the shared system control plane.</p></div></div></section>
 </div>
}
function Toggle({label,checked,onChange}:{label:string;checked:boolean;onChange:(value:boolean)=>void}){return <label className="flex items-start gap-3 text-sm"><input type="checkbox" className="mt-1" checked={checked} onChange={e=>onChange(e.target.checked)}/><span><b>{label}</b><br/><small className="text-muted-foreground">Authorized administrator/IT control.</small></span></label>}
