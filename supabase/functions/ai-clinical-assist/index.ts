import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const MODEL = 'google/gemini-2.5-flash';

interface Body {
  mode: 'report' | 'recommend' | 'synthesize_protocol' | 'portal' | 'clinical_context' | 'nurse_dashboard';
  patientId?: string;
  encounterId?: string;
  diagnosis?: string;
  context?: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const body: Body = await req.json();
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace(/^Bearer\s+/i, '');
    if (!token) throw new Error('Authentication required');

    const authClient = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data: authData, error: authError } = await authClient.auth.getUser(token);
    if (authError || !authData.user) throw new Error('Authentication required');

    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const callerId = authData.user.id;
    const { data: callerRoles, error: callerRolesError } = await supabase.from('user_roles').select('role').eq('user_id', callerId);
    if (callerRolesError || !callerRoles?.length) throw new Error('Authorisation role not found');
    const callerRoleSet = new Set((callerRoles ?? []).map((row) => String(row.role ?? '')));
    const hasAnyRole = (roles: string[]) => roles.some((role) => callerRoleSet.has(role));
    const clinicalRoles = ['admin','practitioner','nurse','midwife','specialist_nurse','radiologist'];
    const aiClinicalRoles = [...clinicalRoles, 'pharmacist'];
    const requireClinicalRole = () => { if (!hasAnyRole(aiClinicalRoles)) throw new Error('Not authorised'); };
    const requirePatientContextRole = () => { if (!hasAnyRole(['admin','practitioner','nurse','midwife','specialist_nurse'])) throw new Error('Not authorised for full clinical context'); };
    const requireProtocolRole = () => { if (!hasAnyRole(['admin','practitioner'])) throw new Error('Not authorised for protocol synthesis'); };
    const requirePatientId = () => { if (!body.patientId) throw new Error('A patient is required'); };

    let systemPrompt = '';
    let userPrompt = '';

    if (body.mode === 'portal') {
      const { data: patient, error: patientError } = await supabase.from('patients').select('id,patient_code,first_name,last_name,date_of_birth,sex,phone,email').eq('user_id', callerId).maybeSingle();
      if (patientError) throw patientError;
      if (!patient) throw new Error('Patient portal profile not found');
      const [{ data: appointments, error: appointmentsError }, { data: videoSessions, error: videoError }, { data: invoices, error: invoicesError }, { data: reports, error: reportsError }] = await Promise.all([
        supabase.from('appointments').select('id,patient_id,scheduled_at,reason,status,department,treatment_status').eq('patient_id', patient.id).order('scheduled_at', { ascending: false }).limit(25),
        supabase.from('video_sessions').select('id,patient_id,scheduled_at,status,payment_received,room_name').eq('patient_id', patient.id).order('scheduled_at', { ascending: false }).limit(25),
        supabase.from('invoices').select('id,patient_id,invoice_number,total_amount,status,created_at').eq('patient_id', patient.id).order('created_at', { ascending: false }).limit(25),
        supabase.rpc('get_ai_report_requests', { _patient_id: patient.id, _limit: 25 }),
      ]);
      const portalErrors = [appointmentsError, videoError, invoicesError, reportsError].filter(Boolean);
      if (portalErrors.length) throw portalErrors[0];
      return new Response(JSON.stringify({ patient, appointments: appointments ?? [], video_sessions: videoSessions ?? [], invoices: invoices ?? [], reports: reports ?? [] }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    if (body.mode === 'clinical_context') {
      requirePatientContextRole();
      requirePatientId();
      const { data: scopedContext, error: contextError } = await supabase.rpc('get_ai_clinical_context', { _patient_id: body.patientId });
      if (contextError) throw contextError;
      if (!scopedContext) throw new Error('Clinical context unavailable');
      return new Response(JSON.stringify({ generatedAt: new Date().toISOString(), ...scopedContext }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    if (body.mode === 'nurse_dashboard') {
      const allowedRoles = ['admin','nurse','specialist_nurse','midwife'];
      if (!hasAnyRole(allowedRoles)) throw new Error('Not authorised');
      const [
        { data: patients, error: patientsError },
        { data: admissionWorkspace, error: admissionError },
        { data: medications, error: medicationsError },
        { data: handovers, error: handoversError },
        { data: triage, error: triageError },
        { data: queue, error: queueError },
      ] = await Promise.all([
        supabase.from('patients').select('id,patient_code,first_name,last_name').order('created_at', { ascending: false }).limit(500),
        supabase.rpc('get_admission_workspace', { _limit: 250 }),
        supabase.from('medication_administrations').select('id,patient_id,prescription_id,medication_name,dose,route,scheduled_at,administered_at,status,reason,administered_by,witnessed_by,notes,due_window_minutes,locked_at,lock_reason,reopened_at,reopen_reason,created_at,updated_at').order('scheduled_at', { ascending: true }).limit(250),
        supabase.from('nursing_shift_handovers').select('id,patient_id,admission_id,outgoing_officer,incoming_officer,shift_date,shift_name,clinical_summary,outstanding_tasks,risks_and_alerts,escalation_required,acknowledged_at,created_at,pending_tasks,safety_concerns,shift_label').order('created_at', { ascending: false }).limit(100),
        supabase.from('triage_assessments').select('id,patient_id,recorded_by,systolic,diastolic,heart_rate,temperature,respiratory_rate,oxygen_saturation,weight_kg,height_m,pain_score,consciousness,presenting_complaint,clinical_notes,priority,is_critical,created_at,updated_at,bmi').order('created_at', { ascending: false }).limit(150),
        supabase.from('department_queues').select('id,patient_id,department,status,priority,reason,related_encounter_id,related_invoice_id,payment_required,payment_satisfied,assigned_to,created_at,updated_at,completed_at,service_order_id,queued_at,claimed_by,claimed_at').eq('department', 'nursing').in('status', ['queued', 'claimed']).order('created_at', { ascending: true }).limit(150),
      ]);
      const dashboardErrors = [patientsError, admissionError, medicationsError, handoversError, triageError, queueError].filter(Boolean);
      if (dashboardErrors.length) throw dashboardErrors[0];
      const admissions = admissionWorkspace?.admissions ?? [];
      return new Response(JSON.stringify({ patients: patients ?? [], admissions, medications: medications ?? [], handovers: handovers ?? [], triage: triage ?? [], queue: queue ?? [] }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const apiKey = Deno.env.get('LOVABLE_API_KEY');
    if (!apiKey) throw new Error('LOVABLE_API_KEY not configured');

    if (body.mode === 'report') {
      requirePatientId();
      const { data: ownerPatient, error: ownerPatientError } = await supabase.from('patients').select('id').eq('id', body.patientId).eq('user_id', callerId).maybeSingle();
      if (ownerPatientError) throw ownerPatientError;
      const isOwner = Boolean(ownerPatient);
      const isClinical = hasAnyRole(aiClinicalRoles);
      if (!isOwner && !isClinical) throw new Error('Not authorised to generate this report');
      const contextRpc = isClinical ? 'get_ai_clinical_context' : 'get_patient_hub_clinical_snapshot';
      const { data: scopedContext, error: contextError } = await supabase.rpc(contextRpc, { _patient_id: body.patientId });
      if (contextError) throw contextError;
      if (!scopedContext) throw new Error('Clinical context unavailable');

      systemPrompt = 'You are a senior clinical AI generating a printable medical summary report. Use clear sections: Patient overview, Vitals, Recent encounters, Diagnoses, Lab findings, Treatment plan, Recommendations. Use markdown.';
      userPrompt = `Generate a comprehensive medical report from the following authorized clinical context. Do not invent findings and clearly distinguish documented findings from recommendations.\\n\\nCLINICAL CONTEXT:\\n${JSON.stringify(scopedContext)}`;
    } else if (body.mode === 'recommend') {
      requireClinicalRole();
      if (!body.diagnosis?.trim()) throw new Error('A diagnosis is required');
      const { data: similar, error: similarError } = await supabase.rpc('get_ai_case_memory_for_diagnosis', { _diagnosis: body.diagnosis, _limit: 20 });
      if (similarError) throw similarError;
      systemPrompt = 'You are a clinical decision-support AI. Given a diagnosis and similar past cases, suggest 3 treatment options with rationale. Stay concise and practical. Use markdown.';
      userPrompt = `Diagnosis: ${body.diagnosis}\nContext: ${body.context ?? ''}\n\nPast similar cases (for reference):\n${JSON.stringify(similar)}`;
    } else if (body.mode === 'synthesize_protocol') {
      requireProtocolRole();
      if (!body.diagnosis?.trim()) throw new Error('A diagnosis is required');
      const { data: cases, error: casesError } = await supabase.rpc('get_ai_case_memory_for_diagnosis', { _diagnosis: body.diagnosis, _limit: 50 });
      if (casesError) throw casesError;
      if (!cases || cases.length < 3) return new Response(JSON.stringify({ error: 'Not enough historical cases to synthesize a protocol (need at least 3).' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      systemPrompt = 'You synthesize an evidence-informed in-house treatment protocol from past cases. Output a single concise protocol document.';
      userPrompt = `Diagnosis: ${body.diagnosis}\nCases (n=${cases.length}):\n${JSON.stringify(cases)}\n\nProduce a protocol with: Indication, Initial assessment, First-line therapy, Monitoring, Escalation.`;
    } else {
      return new Response(JSON.stringify({ error: 'Unknown mode' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const aiRes = await fetch('https://ai.gateway.lovable.dev/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: MODEL, messages: [{ role: 'system', content: systemPrompt }, { role: 'user', content: userPrompt }] }),
    });

    if (aiRes.status === 429) return new Response(JSON.stringify({ error: 'AI rate limit reached, try again shortly.' }), { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    if (aiRes.status === 402) return new Response(JSON.stringify({ error: 'AI credits exhausted. Add funds in Workspace → Usage.' }), { status: 402, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    if (!aiRes.ok) return new Response(JSON.stringify({ error: 'AI gateway error' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

    const data = await aiRes.json();
    const content = data.choices?.[0]?.message?.content ?? '';

    if (body.mode === 'synthesize_protocol' && content) {
      const { error: draftError } = await supabase.rpc('create_ai_protocol_draft', {
        _diagnosis: body.diagnosis,
        _protocol_text: content,
        _case_count: cases?.length ?? 0,
        _icd_code: null,
      });
      if (draftError) throw draftError;
    }

    return new Response(JSON.stringify({ content }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
