import { supabase } from '@/integrations/supabase/client';
import { permissionByHref } from '@/lib/permissions';

export type GlobalSearchKind = 'module' | 'patient' | 'lab' | 'diagnostic' | 'document' | 'accounting' | 'encounter';
export interface GlobalSearchResult { id: string; kind: GlobalSearchKind; title: string; subtitle: string; href: string; score: number; }
type SearchModule = { title: string; description: string; href: string; keywords: string[]; roles?: string[] };

const CLINICAL_ROLES = ['practitioner','nurse','midwife','specialist_nurse','radiologist','radiology_technician','lab_technician'];
const ACCOUNTING_ROLES = ['accountant'];
const MODULES: SearchModule[] = [
  { title:'Dashboard', description:'Clinical and operational command center', href:'/dashboard', keywords:['home','command center','worklist','counters'] },
  { title:'Patients', description:'Patient registration, search and longitudinal records', href:'/patients', keywords:['patient','person','medical record','empi','registration'] },
  { title:'Appointments', description:'Appointment schedule and treatment worklist', href:'/appointments', keywords:['appointment','schedule','visit','booking'] },
  { title:'Triage & Vitals', description:'Triage assessments, observations and vital alerts', href:'/vitals', keywords:['triage','vitals','observations','critical','alert'] },
  { title:'Encounters', description:'Clinical encounters, diagnoses, treatment and amendments', href:'/encounters', keywords:['encounter','consultation','diagnosis','treatment','clinical note'] },
  { title:'Clinical Operations', description:'Permission-aware clinical workflow hub', href:'/clinical-operations', keywords:['clinical operations','workflow','theatre','maternity','transfusion','procedures','anaesthesia'] },
  { title:'Inpatient', description:'Admissions, movements, ward and bed management', href:'/inpatient', keywords:['inpatient','admission','ward','bed','movement','transfer','discharge'] },
  { title:'Nursing Handover', description:'Shift handover and inpatient nursing workflow', href:'/nursing-handover', keywords:['nursing','handover','shift','care plan'], roles:['admin','nurse','midwife','specialist_nurse'] },
  { title:'Nursing Notes', description:'Routine nursing observations, interventions and evaluations', href:'/nursing-notes', keywords:['nursing','notes','progress note','assessment','intervention'], roles:['admin','nurse','midwife','specialist_nurse'] },
  { title:'Laboratory', description:'Lab orders, samples and results', href:'/laboratory', keywords:['laboratory','lab','test','sample','result','pathology'], roles:['admin',...CLINICAL_ROLES,'front_desk'] },
  { title:'Radiology', description:'Imaging orders and radiology workspace', href:'/radiology', keywords:['radiology','imaging','xray','x-ray','ultrasound','ct','mri'], roles:['admin',...CLINICAL_ROLES] },
  { title:'Clinical Results', description:'Review diagnostic results', href:'/clinical-results', keywords:['results','diagnostic results','lab results','imaging results'], roles:['admin',...CLINICAL_ROLES] },
  { title:'Pharmacy', description:'Medicines, dispensing and inventory', href:'/pharmacy', keywords:['pharmacy','medicine','medication','dispensing','stock'], roles:['admin','pharmacist'] },
  { title:'Medication Administration', description:'Medication administration workflow', href:'/medications', keywords:['medication administration','mar','dose','medicine'], roles:['admin',...CLINICAL_ROLES] },
  { title:'Billing', description:'Patient billing, invoices and billable items', href:'/billing', keywords:['billing','bill','invoice','charge','tariff','accounts receivable'] },
  { title:'Finance', description:'Finance workspace and financial operations', href:'/finance', keywords:['finance','accounts','accounting','payment','revenue','expense'], roles:['admin','accountant','front_desk'] },
  { title:'Accounts Approvals', description:'Accounts and financial approval workflow', href:'/accounts-approvals', keywords:['accounts','approval','finance','payment'], roles:['admin','accountant','front_desk'] },
  { title:'Insurance Claims', description:'Insurance claims and payer operations', href:'/insurance-claims', keywords:['insurance','claim','payer','nhis','coverage'], roles:['admin','accountant'] },
  { title:'Reports Center', description:'Operational, clinical and public-health reporting', href:'/reports', keywords:['report','reporting','export','public health','analytics'], roles:['admin','practitioner','accountant','lab_technician'] },
  { title:'Medical Records', description:'Clinical records and document access', href:'/records', keywords:['records','documents','medical records','files'] },
  { title:'Notifications', description:'Workflow events and acknowledgement queue', href:'/notifications', keywords:['notification','alert','attention','acknowledge'] },
  { title:'Department Queue', description:'Department work queues', href:'/department-queue', keywords:['queue','department','worklist'] },
  { title:'AI Clinical Hub', description:'Assistive AI clinical workspace', href:'/ai-clinical', keywords:['ai','clinical ai','assistant','analysis'], roles:['admin',...CLINICAL_ROLES] },
  { title:'Fertility', description:'Fertility and IVF workflow', href:'/fertility', keywords:['fertility','ivf','reproductive'] },
  { title:'Maternity', description:'Maternity care workflow', href:'/maternity', keywords:['maternity','pregnancy','delivery','antenatal'], roles:['admin','nurse','midwife','specialist_nurse'] },
  { title:'Dental', description:'Dental clinical workspace', href:'/dental', keywords:['dental','dentistry','tooth'] },
  { title:'Procedures', description:'Procedure documentation', href:'/procedures', keywords:['procedure','procedure notes'], roles:['admin',...CLINICAL_ROLES] },
  { title:'Anaesthesia', description:'Anaesthetic assessment and clearance', href:'/anesthesia', keywords:['anaesthesia','anesthesia','pre-op'], roles:['admin',...CLINICAL_ROLES] },
  { title:'Administration', description:'System administration workspace', href:'/administration', keywords:['administration','admin'], roles:['admin'] },
  { title:'IT Support', description:'Technology and operational support workspace', href:'/it-support', keywords:['it','technology','support','troubleshooting'], roles:['admin','it_admin'] },
];

function escapeLike(value: string) { return value.replace(/\\/g,'\\\\').replace(/%/g,'\\%').replace(/_/g,'\\_'); }
function patientLabel(p: any) { return p?.patient_code ? `${p.first_name ?? ''} ${p.last_name ?? ''} · ${p.patient_code}`.trim() : `${p?.first_name ?? ''} ${p?.last_name ?? ''}`.trim(); }
function hasAnyRole(roles: string[], allowed: string[]) { return roles.some(role => allowed.includes(role)); }

export function searchWorkspaceModules(query: string, roles: string[] = [], permissions: string[] = []) {
  const q = query.trim().toLocaleLowerCase();
  if (!q) return [];
  return MODULES.filter(m => {
    if (roles.includes('admin')) return true;
    if (m.roles && !roles.some(role => m.roles?.includes(role))) return false;
    const requiredPermission = permissionByHref[m.href];
    return !requiredPermission || permissions.includes(requiredPermission);
  }).map(m => {
    const haystack = [m.title,m.description,...m.keywords].join(' ').toLocaleLowerCase();
    const title = m.title.toLocaleLowerCase();
    const score = title === q ? 120 : title.startsWith(q) ? 100 : haystack.includes(q) ? 80 : 0;
    return score ? { id: `module:${m.href}`, kind:'module' as const, title:m.title, subtitle:m.description, href:m.href, score } : null;
  }).filter(Boolean) as GlobalSearchResult[];
}

async function runQuery<T>(promise: PromiseLike<{data:T|null; error:any}>, map:(row:T)=>GlobalSearchResult[]) {
  try { const {data,error}=await promise; return error || !data ? [] : map(data); } catch { return []; }
}

export async function searchWorkspaceData(query:string, roles:string[] = []):Promise<GlobalSearchResult[]> {
  const q=escapeLike(query.trim()); if(!q || q.length < 2) return [];
  const term=`%${q}%`;
  const isAdmin = roles.includes('admin');
  const canSearchPatients = isAdmin || roles.includes('patient') || hasAnyRole(roles, [...CLINICAL_ROLES, ...ACCOUNTING_ROLES]);
  const canSearchClinical = isAdmin || hasAnyRole(roles, CLINICAL_ROLES);
  const canSearchDocuments = isAdmin || hasAnyRole(roles, [...CLINICAL_ROLES, ...ACCOUNTING_ROLES]);
  const canSearchOutsideLab = isAdmin || hasAnyRole(roles, ['practitioner','nurse','midwife','specialist_nurse','lab_technician']);
  const canSearchInvoices = isAdmin || hasAnyRole(roles, ['accountant']) || hasAnyRole(roles, CLINICAL_ROLES);
  const canSearchServices = isAdmin || hasAnyRole(roles, ['accountant','front_desk']) || hasAnyRole(roles, CLINICAL_ROLES);
  const canSearchClaims = isAdmin || roles.includes('accountant');

  const queries: Promise<GlobalSearchResult[]>[] = [];
  if (canSearchPatients) {
    queries.push(runQuery(
      supabase.from('patients').select('id,patient_code,first_name,last_name,phone,insurance_number').or(`patient_code.ilike.${term},first_name.ilike.${term},last_name.ilike.${term},phone.ilike.${term},insurance_number.ilike.${term}`).limit(8),
      (rows:any[])=>rows.map(p=>({id:p.id,kind:'patient',title:patientLabel(p),subtitle:[p.phone,p.insurance_number].filter(Boolean).join(' · ')||'Patient record',href:`/patients/${p.id}`,score:70}))
    ));
  }
  if (canSearchClinical) {
    queries.push(
      runQuery(supabase.from('lab_orders').select('id,patient_id,test_name,test_category,priority,status,created_at').or(`test_name.ilike.${term},test_category.ilike.${term},status.ilike.${term}`).order('created_at',{ascending:false}).limit(8),
        (rows:any[])=>rows.map(r=>({id:r.id,kind:'lab',title:r.test_name||'Laboratory order',subtitle:`Patient ${r.patient_id} · ${r.status||'ordered'}`,href:`/laboratory?order=${r.id}`,score:65}))),
      runQuery(supabase.from('imaging_orders').select('id,patient_id,modality,study_name,body_site,priority,status,created_at').or(`study_name.ilike.${term},modality.ilike.${term},body_site.ilike.${term},status.ilike.${term}`).order('created_at',{ascending:false}).limit(8),
        (rows:any[])=>rows.map(r=>({id:r.id,kind:'diagnostic',title:r.study_name||`${r.modality||'Imaging'} study`,subtitle:`Patient ${r.patient_id} · ${r.status||'ordered'}`,href:`/radiology?order=${r.id}`,score:64}))),
      runQuery(supabase.from('diagnoses').select('id,encounter_id,patient_id,diagnosis,icd_code,is_principal,is_provisional,created_at').or(`diagnosis.ilike.${term},icd_code.ilike.${term}`).order('created_at',{ascending:false}).limit(8),
        (rows:any[])=>rows.map(r=>({id:r.id,kind:'diagnostic',title:r.diagnosis||'Diagnosis',subtitle:`Patient ${r.patient_id} · ${r.icd_code||'No ICD code'}`,href:`/encounters?encounter=${r.encounter_id}`,score:62}))),
      runQuery(supabase.from('encounters').select('id,patient_id,encounter_type,chief_complaint,principal_diagnosis,status,created_at,submitted_at,version_no').or(`encounter_type.ilike.${term},chief_complaint.ilike.${term},principal_diagnosis.ilike.${term},status.ilike.${term}`).order('created_at',{ascending:false}).limit(8),
        (rows:any[])=>rows.map(r=>({id:r.id,kind:'encounter',title:r.encounter_type||'Clinical encounter',subtitle:`Patient ${r.patient_id} · ${r.principal_diagnosis||r.chief_complaint||r.status||'encounter'}`,href:`/encounters?encounter=${r.id}`,score:61})))
    );
  }
  if (canSearchDocuments) {
    queries.push(
      runQuery(supabase.from('patient_documents').select('id,patient_id,document_type,file_name,mime_type,created_at').or(`file_name.ilike.${term},document_type.ilike.${term}`).order('created_at',{ascending:false}).limit(8),
        (rows:any[])=>rows.map(r=>({id:r.id,kind:'document',title:r.file_name||r.document_type||'Patient document',subtitle:`Patient ${r.patient_id} · ${r.document_type||'document'}`,href:`/patients/${r.patient_id}`,score:58})))
    );
  }
  if (canSearchOutsideLab) {
    queries.push(runQuery(supabase.from('outside_lab_documents').select('id,patient_id,document_type,title,mime_type,created_at').or(`title.ilike.${term},document_type.ilike.${term}`).order('created_at',{ascending:false}).limit(8),
      (rows:any[])=>rows.map(r=>({id:r.id,kind:'document',title:r.title||r.document_type||'Outside laboratory document',subtitle:`Patient ${r.patient_id} · ${r.document_type||'document'}`,href:'/outside-lab',score:57}))));
  }
  if (canSearchInvoices) {
    queries.push(runQuery(supabase.from('invoices').select('id,invoice_number,patient_id,total_amount,paid_amount,outstanding_amount,status,created_at').or(`invoice_number.ilike.${term},status.ilike.${term}`).order('created_at',{ascending:false}).limit(8),
      (rows:any[])=>rows.map(r=>({id:r.id,kind:'accounting',title:r.invoice_number||'Invoice',subtitle:`Patient ${r.patient_id} · ${r.status||'invoice'} · Outstanding ${r.outstanding_amount??0}`,href:`/billing?invoice=${r.id}`,score:55}))));
  }
  if (canSearchServices) {
    queries.push(runQuery(supabase.from('service_orders').select('id,patient_id,service_name,department,status,service_code,created_at').or(`service_name.ilike.${term},department.ilike.${term},service_code.ilike.${term},status.ilike.${term}`).order('created_at',{ascending:false}).limit(8),
      (rows:any[])=>rows.map(r=>({id:r.id,kind:'accounting',title:r.service_name||r.service_code||'Service order',subtitle:`Patient ${r.patient_id} · ${r.department||'service'} · ${r.status||'ordered'}`,href:`/billing?serviceOrder=${r.id}`,score:54}))));
  }
  if (canSearchClaims) {
    queries.push(runQuery(supabase.from('insurance_claims').select('id,patient_id,claim_number,payer_name,status,amount_claimed,amount_paid,created_at').or(`claim_number.ilike.${term},payer_name.ilike.${term},status.ilike.${term}`).order('created_at',{ascending:false}).limit(8),
      (rows:any[])=>rows.map(r=>({id:r.id,kind:'accounting',title:r.claim_number||'Insurance claim',subtitle:`Patient ${r.patient_id} · ${r.payer_name||'payer'} · ${r.status||'claim'}`,href:`/insurance-claims?claim=${r.id}`,score:53}))));
  }

  const results = (await Promise.all(queries)).flat();
  return results.sort((a,b)=>b.score-a.score).slice(0,24);
}

export async function searchGlobalWorkspace(query:string, roles:string[]=[], permissions:string[] = []) {
  const [modules,data]=await Promise.all([Promise.resolve(searchWorkspaceModules(query,roles,permissions)),searchWorkspaceData(query,roles)]);
  return [...modules,...data].sort((a,b)=>b.score-a.score).slice(0,30);
}
