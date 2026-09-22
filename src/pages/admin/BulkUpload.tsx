import { useState } from 'react';
import Papa from 'papaparse';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Upload, Database, FileSpreadsheet, CheckCircle2, AlertTriangle, Download } from 'lucide-react';
import { playSuccessSound } from '@/lib/sounds';

type Entity = 'patients' | 'pharmacy_inventory' | 'icd_codes' | 'staff';
const SCHEMAS: Record<Entity, { label:string; required:string[]; optional:string[]; sample:string; describe:string }> = {
  patients:{label:'Patients',required:['first_name','last_name'],optional:['date_of_birth','gender','phone','email','address','city','ghana_card_number','blood_group','genotype','allergies','chronic_conditions','insurance_provider','insurance_number','emergency_contact_name','emergency_contact_phone'],sample:'first_name,last_name,date_of_birth,gender,phone,email,ghana_card_number
Jane,Doe,1990-04-12,female,+233200000000,jane@example.com,GHA-123456789-0',describe:'Bulk import patient demographics. Writes are performed by the server-authorized import function.'},
  pharmacy_inventory:{label:'Pharmacy inventory & drugs',required:['drug_name'],optional:['generic_name','strength','form','stock_quantity','reorder_level','unit_price','supplier','expiry_date'],sample:'drug_name,generic_name,strength,form,stock_quantity,reorder_level,unit_price,supplier,expiry_date
Paracetamol,Acetaminophen,500mg,tablet,500,50,0.50,MedSupply Ghana,2027-12-31',describe:'Add approved opening inventory through the server-authorized import function.'},
  icd_codes:{label:'ICD-10 codes',required:['code','description'],optional:['version','category'],sample:'code,description,version,category
A00,Cholera,ICD-10,Infectious',describe:'Reference codes written through the server-authorized import function.'},
  staff:{label:'Staff / user accounts',required:['email','first_name','last_name','role'],optional:['phone','department','specialization','onboarding','password'],sample:'email,first_name,last_name,role,onboarding,department
user@example.com,Jane,Doe,nurse,invite,Maternity',describe:'Creates real authenticated accounts through the server-authorized onboarding boundary. Never creates orphan profiles or roles.'},
};
interface JobLog{id:string;entity_type:string;file_name:string|null;total_rows:number;successful_rows:number;failed_rows:number;status:string;created_at:string;errors:any}
export default function BulkUpload(){
  const {user}=useAuth(); const isAdmin=user?.role==='admin';
  const [entity,setEntity]=useState<Entity>('patients'); const [rows,setRows]=useState<Record<string,string>[]>([]);
  const [filename,setFilename]=useState(''); const [importing,setImporting]=useState(false); const [history,setHistory]=useState<JobLog[]>([]); const [previewOnly,setPreviewOnly]=useState(true); const [errors,setErrors]=useState<string[]>([]);
  const loadHistory=async()=>{const {data}=await supabase.from('bulk_import_jobs').select('id,entity_type,file_name,total_rows,successful_rows,failed_rows,status,created_at').order('created_at',{ascending:false}).limit(20);setHistory((data??[]) as JobLog[]);};
  const handleFile=(file:File)=>{setFilename(file.name);Papa.parse(file,{header:true,skipEmptyLines:true,transformHeader:h=>h.trim().toLowerCase(),complete:r=>{setRows(r.data as Record<string,string>[]);setErrors([]);toast({title:'CSV parsed',description:r.data.length+' rows ready for review.'});},error:e=>toast({title:'Parse error',description:e.message,variant:'destructive'})});};
  const downloadTemplate=()=>{const blob=new Blob([SCHEMAS[entity].sample],{type:'text/csv'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=entity+'_template.csv';a.click();URL.revokeObjectURL(url);};
  const validate=(row:Record<string,string>,idx:number)=>{for(const r of SCHEMAS[entity].required)if(!row[r]?.trim())return 'Row '+(idx+2)+': missing required "'+r+'"';if(entity==='patients'&&row.email&&!/^[^@s]+@[^@s]+.[^@s]+$/.test(row.email))return 'Row '+(idx+2)+': invalid email';return null;};
  const performImport=async()=>{if(!rows.length)return;setImporting(true);const localErrors=rows.map(validate).filter(Boolean) as string[];const valid=rows.filter((r,i)=>!validate(r,i));setErrors(localErrors);
    if(!valid.length){setImporting(false);toast({title:'No valid rows',description:localErrors[0]??'Fix the import and retry.',variant:'destructive'});return;}
    const action=entity==='staff'?'bulk_create_users':'import_rows';
    const {data,error}=await supabase.functions.invoke('admin-bulk-import',{body:{action,entity:entity==='staff'?undefined:entity,filename,rows:valid}});
    setImporting(false);
    if(error||data?.error){toast({title:'Import failed',description:data?.error??error?.message??'Import rejected',variant:'destructive'});return;}
    const remoteErrors=entity==='staff'?(data?.results??[]).filter((r:any)=>r.status==='failed').map((r:any)=>'Row '+r.row+': '+r.error):(data?.errors??[]).map((r:any)=>'Row '+r.row+': '+r.reason);
    setErrors([...localErrors,...remoteErrors]);const inserted=entity==='staff'?Number(data?.created_rows??0):Number(data?.inserted_rows??0);
    toast({title:'Import complete',description:inserted+'/'+valid.length+' rows processed'+(remoteErrors.length?' · '+remoteErrors.length+' failed':''),variant:remoteErrors.length===valid.length?'destructive':'default'});
    if(inserted)playSuccessSound();setRows([]);setFilename('');await loadHistory();
  };
  if(!isAdmin)return <div className="p-8 text-center"><AlertTriangle className="w-10 h-10 text-warning mx-auto mb-2"/><h2 className="font-heading text-xl">Admin only</h2><p className="text-muted-foreground text-sm">Administrator privileges are required.</p></div>;
  const preview=rows.slice(0,10);const headers=preview.length?Object.keys(preview[0]):[];
  return <div className="space-y-6 animate-fade-in"><div><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Database className="w-6 h-6 text-primary"/>Bulk Database Upload</h1><p className="text-muted-foreground">Administrative imports are server-authorized. Staff provisioning creates real Auth users only.</p></div>
    <div className="card-medical p-5 space-y-4"><div className="grid md:grid-cols-2 gap-3"><label className="text-sm"><span className="font-medium">Entity</span><select value={entity} onChange={e=>{setEntity(e.target.value as Entity);setRows([]);setFilename('');setErrors([]);}} className="input-medical w-full mt-1">{Object.entries(SCHEMAS).map(([k,v])=><option key={k} value={k}>{v.label}</option>)}</select></label><div className="flex items-end"><button onClick={downloadTemplate} className="btn-ghost flex items-center gap-2"><Download className="w-4 h-4"/>Download CSV template</button></div></div>
    <div className="rounded-lg bg-muted/40 p-3 text-xs"><p className="font-medium mb-1">{SCHEMAS[entity].describe}</p><p><strong>Required:</strong> {SCHEMAS[entity].required.join(', ')}</p><p><strong>Optional:</strong> {SCHEMAS[entity].optional.join(', ')}</p></div>
    <input type="file" accept=".csv,text/csv" onChange={e=>e.target.files?.[0]&&handleFile(e.target.files[0])} className="input-medical w-full"/>
    {rows.length>0&&<div className="space-y-3"><div className="flex items-center justify-between"><p className="text-sm flex items-center gap-2"><FileSpreadsheet className="w-4 h-4"/><strong>{filename}</strong> · {rows.length} rows ready</p><label className="text-xs flex items-center gap-2"><input type="checkbox" checked={previewOnly} onChange={e=>setPreviewOnly(e.target.checked)}/>Preview first 10</label></div>
    <div className="overflow-x-auto rounded-lg border border-border"><table className="text-xs w-full"><thead className="bg-muted/40"><tr>{headers.map(h=><th key={h} className="text-left px-2 py-1 font-medium">{h}</th>)}</tr></thead><tbody>{(previewOnly?preview:rows).map((r,i)=><tr key={i} className="border-t border-border">{headers.map(h=><td key={h} className="px-2 py-1 truncate max-w-[200px]">{r[h]}</td>)}</tr>)}</tbody></table></div>
    <button onClick={()=>void performImport()} disabled={importing} className="btn-primary flex items-center gap-2"><Upload className="w-4 h-4"/>{importing?'Importing…':'Import '+rows.length+' rows'}</button></div>}</div>
    {errors.length>0&&<div className="card-medical p-5"><h2 className="font-semibold text-critical">Import issues</h2><ul className="text-xs list-disc pl-5">{errors.slice(0,50).map((e,i)=><li key={i}>{e}</li>)}</ul></div>}
    <div className="card-medical p-5"><div className="flex justify-between items-center mb-3"><h2 className="font-semibold">Import history</h2><button onClick={()=>void loadHistory()} className="btn-ghost text-xs">Refresh</button></div><p className="text-xs text-muted-foreground">Write-side history is recorded server-side; reads remain governed by RLS.</p>{history.map(h=><div key={h.id} className="rounded-xl border border-border p-3 text-sm mt-2"><div className="flex justify-between"><span className="font-medium flex items-center gap-2">{h.status==='completed'?<CheckCircle2 className="w-4 h-4 text-success"/>:<AlertTriangle className="w-4 h-4 text-critical"/>}{h.entity_type} — {h.file_name??'untitled'}</span><span className="text-xs text-muted-foreground">{new Date(h.created_at).toLocaleString()}</span></div><p className="text-xs text-muted-foreground mt-1">{h.successful_rows}/{h.total_rows} inserted · {h.failed_rows} failed</p></div>)}</div>
  </div>;
}
