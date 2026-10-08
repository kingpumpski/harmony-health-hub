import { useCallback, useEffect, useState } from 'react';
import { BriefcaseBusiness, Plus, RefreshCw, Users } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

type Employee={id:string;employee_number:string;first_name:string;last_name:string;department:string|null;job_title:string;employment_status:string;base_salary:number;pay_frequency:string;start_date:string};
const db=supabase as any;

async function activeFacilityId(){
  const {data,error}=await db.rpc('current_user_facility_id');
  if(error || !data) throw new Error(error?.message || 'No active facility is selected.');
  return data as string;
}

export default function HumanResources(){
 const[employees,setEmployees]=useState<Employee[]>([]); const[loading,setLoading]=useState(true); const[show,setShow]=useState(false);
 const[form,setForm]=useState({employee_number:'',first_name:'',last_name:'',department:'',job_title:'',start_date:new Date().toISOString().slice(0,10),base_salary:'',pay_frequency:'monthly'});
 const load=useCallback(async()=>{setLoading(true);const{data,error}=await db.from('hr_employees').select('id,employee_number,first_name,last_name,department,job_title,employment_status,base_salary,pay_frequency,start_date').order('last_name');if(error)toast.error(error.message);else setEmployees((data||[]) as Employee[]);setLoading(false)},[]);
 useEffect(()=>{void load()},[load]);
 const save=async()=>{if(!form.employee_number||!form.first_name||!form.last_name||!form.job_title||!form.start_date)return toast.error('Employee number, name, job title and start date are required.');try{const facility_id=await activeFacilityId();const{error}=await db.from('hr_employees').insert({...form,facility_id,base_salary:Number(form.base_salary||0)});if(error)throw error;toast.success('Employee added.');setShow(false);setForm({...form,employee_number:'',first_name:'',last_name:'',department:'',job_title:'',base_salary:''});void load()}catch(e:any){toast.error(e.message||'Unable to add employee.')}};
 return <div className="space-y-6 animate-fade-in">
  <header className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><BriefcaseBusiness className="h-6 w-6 text-primary"/>Human Resources</h1><p className="text-sm text-muted-foreground">Facility workforce master data, employment status and compensation inputs.</p></div><div className="flex gap-2"><button className="btn-secondary h-10 w-10 p-0" aria-label="Refresh" onClick={()=>void load()}><RefreshCw className="h-4 w-4"/></button><button className="btn-primary inline-flex gap-2" onClick={()=>setShow(v=>!v)}><Plus className="h-4 w-4"/>Add employee</button></div></header>
  {show&&<section className="card-medical p-5 space-y-4"><h2 className="font-semibold">Employee record</h2><div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
   {([['employee_number','Employee number'],['first_name','First name'],['last_name','Last name'],['department','Department'],['job_title','Job title'],['start_date','Start date'],['base_salary','Base salary (GHS)']] as const).map(([key,label])=><label key={key} className="text-sm space-y-1"><span>{label}</span><input type={key==='start_date'?'date':key==='base_salary'?'number':'text'} className="input-medical w-full" value={form[key]} onChange={e=>setForm(f=>({...f,[key]:e.target.value}))}/></label>)}
   <label className="text-sm space-y-1"><span>Pay frequency</span><select className="input-medical w-full" value={form.pay_frequency} onChange={e=>setForm(f=>({...f,pay_frequency:e.target.value}))}><option value="monthly">Monthly</option><option value="biweekly">Biweekly</option><option value="weekly">Weekly</option></select></label>
  </div><button className="btn-primary" onClick={()=>void save()}>Save employee</button></section>}
  <section className="card-medical overflow-hidden"><div className="border-b p-4"><div className="flex items-center gap-2 font-semibold"><Users className="h-4 w-4"/>Workforce directory <span className="text-xs text-muted-foreground">({employees.length})</span></div></div>
   <div className="overflow-x-auto"><table className="table-medical w-full"><thead><tr><th>Employee</th><th>Department</th><th>Position</th><th>Status</th><th>Pay</th><th>Start date</th></tr></thead><tbody>{loading?<tr><td colSpan={6} className="p-8 text-center text-sm text-muted-foreground">Loading workforce…</td></tr>:employees.map(e=><tr key={e.id}><td><div className="font-medium">{e.first_name} {e.last_name}</div><div className="text-xs text-muted-foreground">{e.employee_number}</div></td><td>{e.department||'—'}</td><td>{e.job_title}</td><td><span className="badge-success">{e.employment_status}</span></td><td>GHS {Number(e.base_salary||0).toLocaleString(undefined,{minimumFractionDigits:2})} / {e.pay_frequency}</td><td>{e.start_date}</td></tr>)}{!loading&&!employees.length&&<tr><td colSpan={6} className="p-8 text-center text-sm text-muted-foreground">No employees recorded for the current facility.</td></tr>}</tbody></table></div>
  </section>
 </div>;
}