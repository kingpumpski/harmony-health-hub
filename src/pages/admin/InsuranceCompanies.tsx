import { useCallback, useEffect, useState } from 'react';
import { Building2, Pencil, Plus, RefreshCw, Save } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';

interface InsuranceCompany { id:string; code:string; name:string; short_name:string|null; phone:string|null; email:string|null; address:string|null; contact_person:string|null; active:boolean }
const empty = { code:'', name:'', short_name:'', phone:'', email:'', address:'', contact_person:'', active:true };

export default function InsuranceCompanies() {
  const { user } = useAuth();
  const [rows,setRows] = useState<InsuranceCompany[]>([]);
  const [form,setForm] = useState(empty);
  const [editing,setEditing] = useState<string|null>(null);
  const [loading,setLoading] = useState(true);
  const [saving,setSaving] = useState(false);

  const load = useCallback(async () => {
    if (!['admin','it_admin'].includes(user?.role ?? '')) return;
    setLoading(true);
    const { data,error } = await supabase.rpc('list_insurance_companies',{_include_inactive:true} as never);
    setLoading(false);
    if (error) { toast({title:'Insurance companies unavailable',description:error.message,variant:'destructive'}); return; }
    setRows((data ?? []) as InsuranceCompany[]);
  }, [user?.role]);
  useEffect(()=>{ void load(); },[load]);
  const reset=()=>{setForm(empty);setEditing(null);};
  const save=async()=>{
    setSaving(true);
    const rpc=editing?'update_insurance_company':'create_insurance_company';
    const args=editing
      ? {_id:editing,_code:form.code,_name:form.name,_short_name:form.short_name||null,_phone:form.phone||null,_email:form.email||null,_address:form.address||null,_contact_person:form.contact_person||null,_active:form.active}
      : {_code:form.code,_name:form.name,_short_name:form.short_name||null,_phone:form.phone||null,_email:form.email||null,_address:form.address||null,_contact_person:form.contact_person||null};
    const {error}=await supabase.rpc(rpc as never,args as never);
    setSaving(false);
    if(error){toast({title:'Save failed',description:error.message,variant:'destructive'});return;}
    toast({title:editing?'Insurance company updated':'Insurance company created',description:'The master record is now stored in the database.'});
    reset(); await load();
  };
  if(!['admin','it_admin'].includes(user?.role ?? '')) return <div className="card-medical p-6"><h1 className="text-xl font-semibold">Administrator access required</h1></div>;
  return <div className="space-y-6 animate-fade-in">
    <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
      <div><h1 className="text-2xl font-heading font-bold">Insurance Companies</h1><p className="text-muted-foreground">Maintain the authoritative payer master used by insurance cases, claims and tariffs.</p></div>
      <button type="button" onClick={reset} className="btn-primary"><Plus className="h-4 w-4" />New insurer</button>
    </div>
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_420px]">
      <section className="card-medical overflow-hidden">
        <div className="flex items-center justify-between border-b border-border p-4"><div className="flex items-center gap-2"><Building2 className="h-5 w-5" /><span className="font-semibold">Payer directory</span></div><button type="button" onClick={()=>void load()} className="btn-secondary"><RefreshCw className="h-4 w-4" />Refresh</button></div>
        {loading ? <p className="p-6 text-sm text-muted-foreground">Loading insurers…</p> : rows.length===0 ? <p className="p-6 text-sm text-muted-foreground">No insurance companies configured yet.</p> : <div className="divide-y divide-border">{rows.map(row => <div key={row.id} className="flex items-center justify-between gap-4 p-4">
          <div><div className="font-medium">{row.name} <span className="ml-2 rounded-full bg-muted px-2 py-0.5 text-xs">{row.code}</span></div><div className="mt-1 text-xs text-muted-foreground">{row.contact_person || 'No contact'}{row.phone ? ' · '+row.phone : ''}{!row.active ? ' · Inactive' : ''}</div></div>
          <button type="button" className="btn-secondary" onClick={()=>{setEditing(row.id);setForm({code:row.code,name:row.name,short_name:row.short_name??'',phone:row.phone??'',email:row.email??'',address:row.address??'',contact_person:row.contact_person??'',active:row.active});}}><Pencil className="h-4 w-4" />Edit</button>
        </div>)}</div>}
      </section>
      <section className="card-medical p-5">
        <div className="mb-4"><h2 className="text-lg font-semibold">{editing?'Edit insurance company':'Create insurance company'}</h2><p className="text-sm text-muted-foreground">Only Admin and IT Admin can change insurer master data.</p></div>
        <div className="space-y-3">
          {([['code','Code'],['name','Name'],['short_name','Short name'],['phone','Phone'],['email','Email'],['contact_person','Contact person'],['address','Address']] as const).map(([key,label])=><label key={key} className="block text-sm font-medium">{label}<input value={form[key]} onChange={e=>setForm(prev=>({...prev,[key]:e.target.value}))} className="input-medical mt-1" /></label>)}
          {editing && <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.active} onChange={e=>setForm(prev=>({...prev,active:e.target.checked}))} />Active</label>}
          <div className="flex gap-2 pt-2"><button type="button" onClick={reset} className="btn-secondary">Clear</button><button type="button" onClick={()=>void save()} disabled={saving} className="btn-primary"><Save className="h-4 w-4" />{saving?'Saving…':editing?'Update insurer':'Create insurer'}</button></div>
        </div>
      </section>
    </div>
  </div>;
}