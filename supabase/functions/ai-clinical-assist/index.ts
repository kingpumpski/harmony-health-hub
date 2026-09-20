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
    const token = authHeader.replace(/^Bearer\\s+/i, '');
    if (!token) throw new Error('Authentication required');

    const authClient = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data: authData, error: authError } = await authClient.auth.getUser(token);
    if (authError || !authData.user) throw new Error('Authentication required');

    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const callerId = authData.user.id;
    const { data: callerProfile, error: callerProfileError } = await supabase.from('profiles').select('role').eq('id', callerId).maybeSingle();
    if (callerProfileError || !callerProfile) throw new Error('Authorisation profile not found');
    const callerRole = String(callerProfile?.role ?? '');
    const clinicalRoles = ['admin','practitioner','nurse','midwife','specialist_nurse','radiologist'];
    const aiClinicalRoles = [...clinicalRoles, 'pharmacist'];
    const requireClinicalRole = () => { if (!aiClinicalRoles.includes(callerRole)) throw new Error('Not authorised'); };
    const requirePatientContextRole = () => { if (!['admin','practitioner','nurse','midwife','specialist_nurse'].includes(callerRole)) throw new Error('Not authorised for full clinical context'); };
    const requireProtocolRole = () => { if (!['admin','practitioner'].includes(callerRole)) throw new Error('Not authorised for protocol synthesis'); };
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
      const pid = body.patientId;
      const { data: patient, error: patientError } = await supabase.from('patients').select('id,patient_code,first_name,last_name,date_of_birth,sex,phone,email').eq('id', pid).maybeSingle();
      if (patientError) throw patientError;
      if (!patient) throw new Error('Patient record not found');
      const [{ data: appointments, error: appointmentsError }, { data: vitals, error: vitalsError }, { data: triage, error: triageError }, { data: encounters, error: encountersError }, { data: labOrders, error: labOrdersError }, { data: prescriptions, error: prescriptionsError }, { data: imagingOrders, error: imagingOrdersError }, { data: procedureNotes, error: procedureNotesError }, { data: anestheticAssessments, error: anestheticAssessmentsError }, { data: admissionHistory, error: admissionError }] = await Promise.all([
        supabase.from('appointments').select('*').eq('patient_id', pid).order('scheduled_at', { ascending: false }).limit(25),
        supabase.from('vital_signs').select('*').eq('patient_id', pid).order('recorded_at', { ascending: false }).limit(25),
        supabase.from('triage_assessments').select('*').eq('patient_id', pid).order('created_at', { ascending: false }).limit(25),
        supabase.from('encounters').select('*').eq('patient_id', pid).order('created_at', { ascending: false }).limit(25),
        supabase.from('lab_orders').select('*').eq('patient_id', pid).order('created_at', { ascending: false }).limit(25),
        supabase.from('prescriptions').select('*').eq('patient_id', pid).order('created_at', { ascending: false }).limit(25),
        supabase.from('imaging_orders').select('*').eq('patient_id', pid).order('created_at', { ascending: false }).limit(25),
        supabase.from('procedure_notes').select('*').eq('patient_id', pid).order('created_at', { ascending: false }).limit(25),
        supabase.from('anesthetic_assessments').select('*').eq('patient_id', pid).order('created_at', { ascending: false }).limit(25),
        supabase.rpc('get_patient_admission_history', { _patient_id: pid }),
      ]);
      const readErrors = [appointmentsError, vitalsError, triageError, encountersError, labOrdersError, prescriptionsError, imagingOrdersError, procedureNotesError, anestheticAssessmentsError, admissionError].filter(Boolean);
      if (readErrors.length) throw readErrors[0];
      const admissions = admissionHistory ?? [];
      const labIds = (labOrders ?? []).map((row: any) => row.id).filter(Boolean);
      const { data: labResults, error: labResultsError } = labIds.length
        ? await supabase.from('lab_results').select('*').in('lab_order_id', labIds).order('created_at', { ascending: false }).limit(100)
        : { data: [] as any[], error: null };
      if (labResultsError) throw labResultsError;
      const latestTriage = (triage ?? [])[0] as any;
      const bmi = latestTriage?.bmi != null ? Number(latestTriage.bmi) : null;
      const latestBmi = {
        value: bmi,
        category: bmi == null ? 'unavailable' : bmi < 18.5 ? 'underweight' : bmi < 25 ? 'healthy range' : bmi < 30 ? 'overweight' : 'obesity range',
        recordedAt: latestTriage?.created_at ?? null,
        weightKg: latestTriage?.weight_kg != null ? Number(latestTriage.weight_kg) : null,
        heightM: latestTriage?.height_m != null ? Number(latestTriage.height_m) : null,
      };
      return new Response(JSON.stringify({ generatedAt: new Date().toISOString(), patient, latestBmi, appointments: appointments ?? [], vitals: vitals ?? [], triage: triage ?? [], encounters: encounters ?? [], labOrders: labOrders ?? [], labResults: labResults ?? [], prescriptions: prescriptions ?? [], imagingOrders: imagingOrders ?? [], procedureNotes: procedureNotes ?? [], anestheticAssessments: anestheticAssessments ?? [], admissions: admissions ?? [] }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    if (body.mode === 'nurse_dashboard') {
      const allowedRoles = ['admin','nurse','specialist_nurse','midwife'];
      if (!allowedRoles.includes(callerRole)) throw new Error('Not authorised');
      const [{ data: patients }, { data: admissionWorkspace, error: admissionError }, { data: medications }, { data: handovers }, { data: triage }, { data: queue }] = await Promise.all([
        supabase.from('patients').select('id,patient_code,first_name,last_name').order('created_at', { ascending: false }).limit(500),
        supabase.rpc('get_admission_workspace', { _limit: 250 }),
        supabase.from('medication_administrations').select('*').order('scheduled_at', { ascending: true }).limit(250),
        supabase.from('nursing_shift_handovers').select('*').order('created_at', { ascending: false }).limit(100),
        supabase.from('triage_assessments').select('*').order('created_at', { ascending: false }).limit(150),
        supabase.from('department_queues').select('*').eq('department', 'nursing').in('status', ['queued', 'claimed']).order('created_at', { ascending: true }).limit(150),
      ]);
      const dashboardErrors = [patientsError, admissionError, medicationsError, handoversError, triageError, queueError].filter(Boolean);
      if (dashboardErrors.length) throw dashboardErrors[0];
      const admissions = admissionWorkspace?.admissions ?? [];
      return new Response(JSON.stringify({ patients: patients ?? [], admissions, medications: medications ?? [], handovers: handovers ?? [], triage: triage ?? [], queue: queue ?? [] }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const apiKey = Deno.env.get('LOVABLE_API_KEY');
    if (!apiKey) throw new Error('LOVABLE_API_KEY not configured');

    if (body.mode === 'report') {
      requirePatientContextRole();
      requirePatientId();
      const { data: patient, error: patientError } = await supabase.from('patients').select('id,patient_code,first_name,last_name,date_of_birth,sex').eq('id', body.patientId).maybeSingle();
      if (patientError) throw patientError;
      if (!patient) throw new Error('Patient record not found');
      const [{ data: encounters, error: encountersError }, { data: vitals, error: vitalsError }, { data: labs, error: labsError }] = await Promise.all([
        supabase.from('encounters').select('id,patient_id,encounter_type,status,chief_complaint,notes,created_at,diagnoses(*),prescriptions(*)').eq('patient_id', body.patientId).order('created_at', { ascending: false }).limit(5),
        supabase.from('vital_signs').select('id,patient_id,blood_pressure_systolic,blood_pressure_diastolic,pulse,temperature,respiratory_rate,oxygen_saturation,weight_kg,height_cm,recorded_at').eq('patient_id', body.patientId).order('recorded_at', { ascending: false }).limit(3),
        supabase.from('lab_orders').select('id,patient_id,test_name,status,priority,created_at,lab_results(*)').eq('patient_id', body.patientId).order('created_at', { ascending: false }).limit(5),
      ]);
      const reportErrors = [encountersError, vitalsError, labsError].filter(Boolean);
      if (reportErrors.length) throw reportErrors[0];

      systemPrompt = 'You are a senior clinical AI generating a printable medical summary report. Use clear sections: Patient overview, Vitals, Recent encounters, Diagnoses, Lab findings, Treatment plan, Recommendations. Use markdown.';
      userPrompt = `Generate a comprehensive medical report.\n\nPATIENT:\n${JSON.stringify(patient)}\n\nVITALS:\n${JSON.stringify(vitals)}\n\nENCOUNTERS:\n${JSON.stringify(encounters)}\n\nLABS:\n${JSON.stringify(labs)}`;
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
      if (!cases || cases.length < 3) {
        return new Response(JSON.stringify({ error: 'Not enough historical cases to synthesize a protocol (need at least 3).' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }
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
