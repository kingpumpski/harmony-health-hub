import { useEffect, useState } from 'react';
import { Building2, Plus, ShieldCheck, Pencil, Power } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { RecordList, type RecordColumn, StatusBadge } from '@/components/records/RecordList';

type Facility={id:string;name:string;facility_code:string|null;facility_type:string;district:string|null;region:string|null;is_active:boolean;created_at:string};
const types=[['chps_compound','CHPS Compound'],['health_centre','Health Centre'],['district_hospital','District Hospital'],['regional_hospital','Regional Hospital'],['teaching_hospital','Teaching Hospital'],['specialist_hospital','Specialist Hospital'],['polyclinic','Polyclinic'],['clinic','Clinic'],['maternity_home','Maternity Home'],['other','Other']];

export default function PlatformFacilityOnboarding(){
 const {user}=useAuth(); const allowed=user?.role==='system_superuser' || user?.roles.includes('system_superuser');
 const [facilities,setFacilities]=useState<Facility[]>([]); const [loading,setLoading]=useState(true); const [saving,setSaving]=useState(false);
 const [name,setName]=useState(''); const [code,setCode]=useState(''); const [type,setType]=useState('district_hospital'); const [district,setDistrict]=useState(''); const [region,setRegion]=useState(''); const [dhims,setDhims]=useState(''); const [editing,setEditing]=useState<Facility|null>(null);
 const load=async()=>{setLoading(true); const {data,error}=await supabase.rpc('platform_list_facilities'); if(error) toast({title:'Facility directory unavailable',description:error.message,variant:'destructive'}); else setFacilities((data??[]) as Facility[]); setLoading(false);};
 useEffect(()=>{if(allowed) void load(); else setLoading(false);},[allowed]);
 const create=async(e:React.FormEvent)=>{e.preventDefault(); if(!allowed){toast({title:'Access denied',description:'Only a System Superuser can onboard facilities.',variant:'destructive'});return;} if(!name.trim()){toast({title:'Facility name required',description:'Enter the facility name before onboarding.',variant:'destructive'});return;} setSaving(true);const {data,error}=await supabase.rpc('platform_create_facility',{_name:name,_facility_code:code||null,_facility_type:type,_district:district||null,_region:region||null,_dhims2_uid:dhims||null});setSaving(false);if(error){toast({title:'Facility onboarding failed',description:error.message,variant:'destructive'});return;}toast({title:'Facility onboarded',description:String(data?.name??name)+' is now registered on the platform.'});setName('');setCode('');setDistrict('');setRegion('');setDhims('');void load();};
 const edit=async(facility:Facility)=>{setEditing(facility);setName(facility.name);setCode(facility.facility_code??'');setType(facility.facility_type);setDistrict(facility.district??'');setRegion(facility.region??'');setDhims('');};
 const saveEdit=async(e:React.FormEvent)=>{e.preventDefault();if(!editing||!name.trim())return;setSaving(true);const {error}=await supabase.rpc('platform_update_facility',{_facility_id:editing.id,_name:name,_facility_code:code||null,_facility_type:type,_district:district||null,_region:region||null,_dhims2_uid:dhims||null});setSaving(false);if(error)return toast({title:'Facility update failed',description:error.message,variant:'destructive'});toast({title:'Facility updated',description:name+' was updated.'});setEditing(null);setName('');setCode('');setDistrict('');setRegion('');setDhims('');void load();};
 const toggle=async(facility:Facility)=>{const next=!facility.is_active;if(!next&&!window.confirm('Deactivate '+facility.name+'? Users must clear active facility context first.'))return;const {error}=await supabase.rpc('platform_set_facility_active',{_facility_id:facility.id,_is_active:next});if(error)return toast({title:'Facility status change failed',description:error.message,variant:'destructive'});toast({title:next?'Facility activated':'Facility deactivated',description:facility.name});void load();};
 const columns:RecordColumn<Facility>[]=[
  {key:'name',header:'Facility',render:r=><div><p className="font-medium">{r.name}</p><p className="text-xs text-muted-foreground">{r.facility_code||'No facility code'}</p></div>},
  {key:'type',header:'Type',hideBelow:'md',render:r=><span className="text-sm">{types.find(x=>x[0]===r.facility_type)?.[1]??r.facility_type}</span>},
  {key:'location',header:'Location',hideBelow:'lg',render:r=><span className="text-sm">{[r.district,r.region].filter(Boolean).join(', ')||'Not specified'}</span>},
  {key:'status',header:'Status',render:r=><StatusBadge status={r.is_active?'Active':'Inactive'}/>}
 ];
 if(!user)return null;
 if(!allowed)return <div className="rounded-2xl border border-warning/30 bg-warning/10 p-5">This platform workspace is restricted to the System Superuser role.</div>;
 return <div className="space-y-6 animate-fade-in">
  <header><div className="flex items-center gap-3"><div className="rounded-xl bg-primary/10 p-3"><Building2 className="h-6 w-6 text-primary"/></div><div><h1 className="text-2xl font-heading font-bold">Facility Onboarding</h1><p className="text-muted-foreground">Platform-level registration and oversight of hospitals and healthcare facilities.</p></div></div></header>
  <div className="grid gap-6 xl:grid-cols-[420px_1fr]">
   <form onSubmit={editing?saveEdit:create} className="card-medical p-6 space-y-4"><div><h2 className="font-semibold">{editing?'Edit facility':'Onboard a facility'}</h2><p className="text-xs text-muted-foreground mt-1">Creates the facility as a platform entity. Staff memberships are assigned separately during facility administration.</p></div>
    <input className="input-medical w-full" placeholder="Facility / hospital name" value={name} onChange={e=>setName(e.target.value)} required/>
    <input className="input-medical w-full" placeholder="Facility code (optional)" value={code} onChange={e=>setCode(e.target.value)}/>
    <select className="input-medical w-full" value={type} onChange={e=>setType(e.target.value)}>{types.map(x=><option key={x[0]} value={x[0]}>{x[1]}</option>)}</select>
    <div className="grid grid-cols-2 gap-2"><input className="input-medical" placeholder="District" value={district} onChange={e=>setDistrict(e.target.value)}/><input className="input-medical" placeholder="Region" value={region} onChange={e=>setRegion(e.target.value)}/></div>
    <input className="input-medical w-full" placeholder="DHIMS2 UID (optional)" value={dhims} onChange={e=>setDhims(e.target.value)}/>
    <div className="flex gap-2"><button className="btn-primary flex-1 inline-flex items-center justify-center gap-2" disabled={saving}><Plus className="h-4 w-4"/>{saving?(editing?'Saving…':'Onboarding…'):(editing?'Save Changes':'Onboard Facility')}</button>{editing&&<button type="button" className="btn-secondary" onClick={()=>{setEditing(null);setName('');setCode('');setDistrict('');setRegion('');setDhims('')}}>Cancel</button>}</div>
    <div className="rounded-xl border border-border bg-muted/30 p-3 text-xs text-muted-foreground flex gap-2"><ShieldCheck className="h-4 w-4 shrink-0 text-primary"/>The platform superuser does not become a facility staff member simply by onboarding the facility.</div>
   </form>
   <RecordList title="Platform Facility Registry" description="All registered facilities visible to the platform superuser." data={facilities} columns={columns} isLoading={loading} rowKey={r=>r.id} onRefresh={()=>void load()} isRefreshing={loading} emptyState={{title:'No facilities onboarded yet.',description:'Use the onboarding form to register the first facility.'}}/>
  </div>
 </div>;
}