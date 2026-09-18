import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

type Body = { module?: string; limit?: number };
const ROLE_MAP: Record<string, string[]> = {
  appointments:['admin','practitioner','nurse','midwife','specialist_nurse','front_desk'], ward:['admin','practitioner','nurse','midwife','specialist_nurse'], nursing_care:['admin','practitioner','nurse','midwife','specialist_nurse'], emergency:['admin','practitioner','nurse','midwife','specialist_nurse'], theatre:['admin','practitioner','nurse','specialist_nurse'], transfusion:['admin','practitioner','nurse','midwife','specialist_nurse'], insurance:['admin','accountant'], medication_administration:['admin','nurse','specialist_nurse','midwife','practitioner'], ai_clinical:['admin','practitioner','nurse','midwife','specialist_nurse','radiologist'], data_migration:['admin'], facilities:['admin','front_desk','accountant'],
};

Deno.serve(async req => {
  const pre=handlePreflight(req); if(pre) return pre;
  const cors=buildCorsHeaders(req);
  const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
  try {
    const token=(req.headers.get('Authorization')??'').replace(/^Bearer\s+/i,'');
    if(!token) return json({error:'Authentication required'},401);
    const body=await req.json() as Body;
    const module=String(body?.module??'').trim();
    const limit=Math.max(1,Math.min(Number(body?.limit??200)||200,500));
    const allowedRoles=ROLE_MAP[module];
    if(!allowedRoles) return json({error:'Unsupported workspace module'},400);

    const anon=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!);
    const {data:authData,error:authError}=await anon.auth.getUser(token);
    if(authError||!authData.user) return json({error:'Authentication required'},401);

    const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const {data:roleRows,error:roleError}=await db.from('user_roles').select('role').eq('user_id',authData.user.id);
    if(roleError) return json({error:'Unable to resolve staff role'},500);
    const assignedRoles=(roleRows??[]).map(row=>String(row.role??'')).filter(Boolean);
    if(assignedRoles.length===0) return json({error:'Staff role required'},403);
    if(!assignedRoles.some(role=>allowedRoles.includes(role))) return json({error:'Not authorised'},403);

    const q=async(table:string,select='*')=>db.from(table).select(select);
    if(module==='appointments'){const{data,error}=await(await q('appointments','id,patient_id,scheduled_at,reason,status,department,attending_officer_id,treatment_status,treatment_notes')).order('scheduled_at',{ascending:true}).limit(limit);if(error)throw error;return json({appointments:data??[]});}
    if(module==='ward'){const[w,b]=await Promise.all([(await q('ward_units','id,name,code,specialty,gender_policy,active')).eq('active',true).order('name').limit(limit),(await q('ward_beds','id,ward_id,bed_number,status,patient_id,admission_id')).order('bed_number').limit(limit)]);if(w.error)throw w.error;if(b.error)throw b.error;return json({wards:w.data??[],beds:b.data??[]});}
    if(module==='nursing_care'){const{data,error}=await(await q('nursing_care_plans','id,patient_id,problem,goal,interventions,priority,status,created_at,updated_at')).order('created_at',{ascending:false}).limit(limit);if(error)throw error;return json({care_plans:data??[]});}
    if(module==='emergency'){const{data,error}=await(await q('emergency_cases','id,patient_id,chief_complaint,acuity,arrival_mode,status,assigned_officer,created_at')).order('created_at',{ascending:false}).limit(limit);if(error)throw error;return json({cases:data??[]});}
    if(module==='theatre'){const{data,error}=await(await q('theatre_cases','id,patient_id,procedure_name,theatre_name,scheduled_start,urgency,status,anesthetist_id')).order('scheduled_start',{ascending:true}).limit(limit);if(error)throw error;return json({cases:data??[]});}
    if(module==='transfusion'){const{data,error}=await(await q('transfusion_records','id,patient_id,blood_product,unit_identifier,blood_group,status,reaction_observed,reaction_notes')).order('created_at',{ascending:false}).limit(limit);if(error)throw error;return json({records:data??[]});}
    if(module==='insurance'){const{data,error}=await(await q('insurance_claims','id,patient_id,payer_name,member_number,claim_number,amount_claimed,amount_approved,amount_paid,status,rejection_reason,service_from,service_to,created_at')).order('created_at',{ascending:false}).limit(limit);if(error)throw error;return json({claims:data??[]});}
    if(module==='medication_administration'){const[r,p]=await Promise.all([(await q('medication_administrations','id,patient_id,medication_name,dose,route,scheduled_at,administered_at,administered_by,status,reason,notes,locked_at,lock_reason,due_window_minutes,reopened_at,reopen_reason')).order('scheduled_at',{ascending:false}).limit(limit),(await q('profiles','id,first_name,last_name,department')).limit(limit)]);if(r.error)throw r.error;if(p.error)throw p.error;return json({records:r.data??[],profiles:p.data??[]});}
    if(module==='ai_clinical'){const{data,error}=await(await q('ai_clinical_sessions','id,specialist,status,review_status,created_at,model_provider,model_name')).order('created_at',{ascending:false}).limit(limit);if(error)throw error;return json({sessions:data??[]});}
    if(module==='data_migration'){const{data,error}=await(await q('data_migration_batches','id,entity_type,source_system,source_version,file_name,total_rows,staged_rows,accepted_rows,rejected_rows,status,created_at,approved_at,completed_at')).eq('entity_type','legacy_clinical_records').order('created_at',{ascending:false}).limit(limit);if(error)throw error;return json({batches:data??[]});}
    const{data,error}=await(await q('healthcare_facilities','id,name,facility_code,facility_type,district,region,dhims2_uid,is_active')).eq('is_active',true).order('name').limit(limit);if(error)throw error;return json({facilities:data??[]});
  } catch(error) {
    const detail=error instanceof Error?error.message:String(error);
    console.error(JSON.stringify({scope:'operational-workspace',error:detail}));
    return json({error:'Operational workspace query failed',code:'WORKSPACE_QUERY_FAILED'},500);
  }
});
