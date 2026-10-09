import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const MODEL = 'google/gemini-2.5-flash';

interface Body {
  mode: 'report' | 'recommend' | 'synthesize_protocol' | 'portal' | 'clinical_context' | 'nurse_dashboard';
  patientId?: string;
  reportRequestId?: string;
  encounterId?: string;
  diagnosis?: string;
  context?: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  let serviceRoleClient: any = null;
  let authorizedPatientReportRequestId: string | null = null;
  const completeAuthorizedPatientReport = async (content: string | null, error: string | null) => {
    if (!serviceRoleClient || !authorizedPatientReportRequestId) return;
    const { error: completionError } = await serviceRoleClient.rpc('complete_ai_report_request', {
      _request_id: authorizedPatientReportRequestId,
      _content: content,
      _error: error,
    });
    if (completionError) throw completionError;
  };

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
    const { data: callerRoles, error: callerRolesError } = await supabase.rpc('get_current_user_roles');
    if (callerRolesError || !callerRoles?.length) throw new Error('Authorisation role not found');
    const callerRoleSet = new Set((callerRoles ?? []).map((role) => String(role ?? '')));
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
      if (!hasAnyRole(['patient'])) throw new Error('Patient portal access is not permitted');
      const { data: patientRows, error: patientError } = await supabase.rpc('get_patient_portal_identity', {});
      if (patientError) throw patientError;
      const patient = Array.isArray(patientRows) ? patientRows[0] : patientRows;
      if (!patient) throw new Error('Patient portal profile not found');
      const portalReads = await Promise.allSettled([

        supabase.rpc('get_patient_appointments', { _patient_id: patient.id, _limit: 25 }),
        supabase.rpc('get_patient_portal_video_sessions', { _limit: 25 }),
        supabase.rpc('get_patient_invoice_summary', { _limit: 25 }),
        supabase.rpc('get_ai_report_requests', { _patient_id: patient.id, _limit: 25 }),
      ]);
      const valueAt = <T,>(index: number, fallback: T): T => {
        const result = portalReads[index];
        return result?.status === 'fulfilled' && !result.value.error ? (result.value.data as T) : fallback;
      };
      const unavailable = portalReads.reduce<string[]>((acc, result, index) => {
        if (result.status === 'rejected' || result.value.error) acc.push(['appointments','video_sessions','invoices','reports'][index]);
        return acc;
      }, []);
      return new Response(JSON.stringify({
        patient,
        appointments: valueAt(0, []),
        video_sessions: valueAt(1, []),
        invoices: valueAt(2, []),
        reports: valueAt(3, []),
        partial: unavailable.length > 0,
        unavailable_sections: unavailable,
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
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
        supabase.rpc('get_patient_directory', { _limit: 500 }),
        supabase.rpc('get_admission_workspace', { _limit: 250 }),
        supabase.from('medication_administrations').select('id,patient_id,prescription_id,medication_name,dose,route,scheduled_at,administered_at,status,reason,administered_by,witnessed_by,notes,due_window_minutes,locked_at,lock_reason,reopened_at,reopen_reason,alert_acknowledged_at,alert_acknowledged_by,created_at,updated_at').order('scheduled_at', { ascending: true }).limit(250),
        supabase.from('nursing_shift_handovers').select('id,patient_id,admission_id,outgoing_officer,incoming_officer,shift_date,shift_name,clinical_summary,outstanding_tasks,risks_and_alerts,escalation_required,acknowledged_at,created_at,pending_tasks,safety_concerns,shift_label').order('created_at', { ascending: false }).limit(100),
        supabase.from('triage_assessments').select('id,patient_id,recorded_by,systolic,diastolic,heart_rate,temperature,respiratory_rate,oxygen_saturation,weight_kg,height_m,pain_score,consciousness,presenting_complaint,clinical_notes,priority,is_critical,created_at,updated_at,bmi').order('created_at', { ascending: false }).limit(150),
        supabase.from('department_queues').select('id,patient_id,department,status,priority,reason,related_encounter_id,related_invoice_id,payment_required,payment_satisfied,assigned_to,created_at,updated_at,completed_at,service_order_id,queued_at,claimed_by,claimed_at').eq('department', 'nursing').in('status', ['queued', 'claimed']).order('created_at', { ascending: true }).limit(150),
      ]);
      const dashboardErrors = [patientsError, admissionError, medicationsError, handoversError, triageError, queueError].filter(Boolean);
      if (dashboardErrors.length) throw dashboardErrors[0];
      const admissions = Array.isArray(admissionWorkspace) ? admissionWorkspace : (admissionWorkspace?.admissions ?? []);
      return new Response(JSON.stringify({ patients: patients ?? [], admissions, medications: medications ?? [], handovers: handovers ?? [], triage: triage ?? [], queue: queue ?? [] }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const apiKey = Deno.env.get('LOVABLE_API_KEY');
    if (!apiKey) throw new Error('LOVABLE_API_KEY not configured');

    if (body.mode === 'report') {
      requirePatientId();
      const isClinical = hasAnyRole(aiClinicalRoles);
      let isPatientOwner = false;

      if (!isClinical && hasAnyRole(['patient'])) {
        const { data: ownedPatient, error: ownershipError } = await supabase
          .from('patients')
          .select('id')
          .eq('id', body.patientId)
          .eq('user_id', callerId)
          .maybeSingle();
        if (ownershipError) throw ownershipError;
        isPatientOwner = Boolean(ownedPatient);

        // Preserve the existing portal identity fallback for legacy test patients
        // whose account is linked by verified email rather than user_id.
        if (!isPatientOwner) {
          const { data: identityRows, error: identityError } = await supabase.rpc('get_patient_portal_identity', {});
          if (identityError) throw identityError;
          const identity = Array.isArray(identityRows) ? identityRows[0] : identityRows;
          isPatientOwner = Boolean(identity?.id && identity.id === body.patientId);
        }
      }

      if (!isClinical && !isPatientOwner) throw new Error('Not authorised to generate this report');

      if (isPatientOwner) {
        if (!body.reportRequestId) throw new Error('A pending report request is required');
        const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
        if (!serviceRoleKey) throw new Error('Report service is not configured');
        serviceRoleClient = createClient(Deno.env.get('SUPABASE_URL')!, serviceRoleKey, {
          auth: { persistSession: false, autoRefreshToken: false },
        });
        const { data: pendingRequest, error: requestError } = await serviceRoleClient
          .from('ai_report_requests')
          .select('id')
          .eq('id', body.reportRequestId)
          .eq('patient_id', body.patientId)
          .eq('requested_by', callerId)
          .eq('status', 'processing')
          .maybeSingle();
        if (requestError) throw requestError;
        if (!pendingRequest) throw new Error('Report request is not owned by this account or is no longer pending');
        authorizedPatientReportRequestId = body.reportRequestId;
      }

      const { data: scopedContext, error: contextError } = isClinical
        ? await supabase.rpc('get_ai_clinical_context', { _patient_id: body.patientId })
        : await supabase.rpc('get_patient_hub_clinical_snapshot', { _patient_id: body.patientId });
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

    if (aiRes.status === 429) {
      await completeAuthorizedPatientReport(null, 'AI rate limit reached, try again shortly.');
      return new Response(JSON.stringify({ error: 'AI rate limit reached, try again shortly.' }), { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    if (aiRes.status === 402) {
      await completeAuthorizedPatientReport(null, 'AI credits are temporarily unavailable. Please try again later.');
      return new Response(JSON.stringify({ error: 'AI credits exhausted. Add funds in Workspace → Usage.' }), { status: 402, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    if (!aiRes.ok) {
      await completeAuthorizedPatientReport(null, 'The report service is temporarily unavailable. Please try again.');
      return new Response(JSON.stringify({ error: 'AI gateway error' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const data = await aiRes.json();
    const content = data.choices?.[0]?.message?.content ?? '';
    if (authorizedPatientReportRequestId && !String(content).trim()) {
      throw new Error('The report service returned no usable content');
    }
    if (authorizedPatientReportRequestId) {
      await completeAuthorizedPatientReport(String(content), null);
    }

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
    if (authorizedPatientReportRequestId && serviceRoleClient) {
      try {
        await completeAuthorizedPatientReport(null, 'Report generation failed. Please try again.');
      } catch (completionError) {
        console.error('Unable to finalize failed AI report request', completionError);
      }
    }
    console.error(e);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
