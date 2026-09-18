import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

type Body = { module: string; limit?: number };

const ROLE_MAP: Record<string, string[]> = {
  appointments: ['admin','practitioner','nurse','midwife','specialist_nurse','front_desk'],
  ward: ['admin','practitioner','nurse','midwife','specialist_nurse'],
  handover: ['admin','practitioner','nurse','midwife','specialist_nurse'],
  nursing_care: ['admin','practitioner','nurse','midwife','specialist_nurse'],
  theatre: ['admin','practitioner','nurse','specialist_nurse'],
  transfusion: ['admin','practitioner','nurse','midwife','specialist_nurse'],
  insurance: ['admin','accountant'],
  medication_administration: ['admin','nurse','specialist_nurse','midwife','practitioner'],
  ai_clinical: ['admin','practitioner','nurse','midwife','specialist_nurse','radiologist'],
  data_migration: ['admin'],
  facilities: ['admin','front_desk','accountant'],
};

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  const cors = buildCorsHeaders(req);
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { ...cors, 'Content-Type': 'application/json' },
  });

  try {
    const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!token) return json({ error: 'Authentication required' }, 401);

    const anon = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!);
    const { data: authData, error: authError } = await anon.auth.getUser(token);
    if (authError || !authData.user) return json({ error: 'Authentication required' }, 401);

    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: profile, error: profileError } = await db.from('profiles').select('role').eq('id', authData.user.id).maybeSingle();
    if (profileError) return json({ error: profileError.message }, 500);
    const role = String(profile?.role ?? '');
    if (!role) return json({ error: 'Staff profile required' }, 403);

    const body = await req.json() as Body;
    const module = String(body?.module ?? '').trim();
    const limit = Math.max(1, Math.min(Number(body?.limit ?? 200) || 200, 500));
    const allowed = ROLE_MAP[module];
    if (!allowed) return json({ error: 'Unsupported workspace module' }, 400);
    if (!allowed.includes(role)) return json({ error: 'Not authorised' }, 403);

    const q = async (table: string, select = '*') => db.from(table).select(select);

    if (module === 'appointments') {
      const { data, error } = await (await q('appointments','id,patient_id,scheduled_at,reason,status,department,attending_officer_id,treatment_status,treatment_notes')).order('scheduled_at',{ascending:true}).limit(limit);
      if (error) throw error; return json({ appointments: data ?? [] });
    }
    if (module === 'ward') {
      const [w,b] = await Promise.all([
        (await q('ward_units','id,name,code,specialty,gender_policy,active')).eq('active',true).order('name').limit(limit),
        (await q('ward_beds','id,ward_id,bed_number,status,patient_id,admission_id')).order('bed_number').limit(limit),
      ]);
      if (w.error) throw w.error; if (b.error) throw b.error;
      return json({ wards:w.data??[], beds:b.data??[] });
    }
    if (module === 'handover') {
      const { data,error }=await (await q('nursing_shift_handovers','id,patient_id,shift_label,clinical_summary,pending_tasks,safety_concerns,escalation_required,acknowledged_at,created_at')).order('created_at',{ascending:false}).limit(limit);
      if(error) throw error; return json({handovers:data??[]});
    }
    if (module === 'nursing_care') {
      const { data,error }=await (await q('nursing_care_plans','id,patient_id,problem,goal,interventions,priority,status,created_at,updated_at')).order('created_at',{ascending:false}).limit(limit);
      if(error) throw error; return json({care_plans:data??[]});
    }
    if (module === 'theatre') {
      const [c,p]=await Promise.all([
        (await q('theatre_cases','id,patient_id,procedure_name,theatre_name,scheduled_start,urgency,status,anesthetist_id')).order('scheduled_start',{ascending:true}).limit(limit),
        (await q('profiles','id,full_name,specialization')).in('role',['practitioner','nurse','specialist_nurse']).order('full_name').limit(limit),
      ]);
      if(c.error) throw c.error; if(p.error) throw p.error; return json({cases:c.data??[],profiles:p.data??[]});
    }
    if (module === 'transfusion') {
      const { data,error }=await (await q('transfusion_records','id,patient_id,blood_product,unit_identifier,blood_group,status,reaction_observed,reaction_notes')).order('created_at',{ascending:false}).limit(limit);
      if(error) throw error; return json({records:data??[]});
    }
    if (module === 'insurance') {
      const { data,error }=await (await q('insurance_claims','id,patient_id,payer_name,member_number,claim_number,amount_claimed,amount_approved,amount_paid,status,rejection_reason,service_from,service_to,created_at')).order('created_at',{ascending:false}).limit(limit);
      if(error) throw error; return json({claims:data??[]});
    }
    if (module === 'medication_administration') {
      const [r,p]=await Promise.all([
        (await q('medication_administrations','id,patient_id,medication_name,dose,route,scheduled_at,administered_at,administered_by,status,reason,notes,locked_at,lock_reason,due_window_minutes,reopened_at,reopen_reason')).order('scheduled_at',{ascending:false}).limit(limit),
        (await q('profiles','id,first_name,last_name,department')).limit(limit),
      ]);
      if(r.error) throw r.error; if(p.error) throw p.error; return json({records:r.data??[],profiles:p.data??[]});
    }
    if (module === 'ai_clinical') {
      const { data,error }=await (await q('ai_clinical_sessions','id,specialist,status,review_status,created_at,model_provider,model_name')).order('created_at',{ascending:false}).limit(limit);
      if(error) throw error; return json({sessions:data??[]});
    }
    if (module === 'data_migration') {
      const { data,error }=await (await q('data_migration_batches','id,entity_type,source_system,source_version,file_name,total_rows,staged_rows,accepted_rows,rejected_rows,status,created_at,approved_at,completed_at')).eq('entity_type','legacy_clinical_records').order('created_at',{ascending:false}).limit(limit);
      if(error) throw error; return json({batches:data??[]});
    }
    const { data,error }=await (await q('healthcare_facilities','id,name,facility_code,facility_type,district,region,dhims2_uid,is_active')).eq('is_active',true).order('name').limit(limit);
    if(error) throw error; return json({facilities:data??[]});
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
