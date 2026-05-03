import { corsHeaders } from '@supabase/supabase-js/cors';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const MODEL = 'google/gemini-2.5-flash';

interface Body {
  mode: 'report' | 'recommend' | 'synthesize_protocol';
  patientId?: string;
  encounterId?: string;
  diagnosis?: string;
  context?: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const body: Body = await req.json();
    const apiKey = Deno.env.get('LOVABLE_API_KEY');
    if (!apiKey) throw new Error('LOVABLE_API_KEY not configured');

    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    let systemPrompt = '';
    let userPrompt = '';

    if (body.mode === 'report') {
      const { data: patient } = await supabase.from('patients').select('*').eq('id', body.patientId).maybeSingle();
      const { data: encounters } = await supabase.from('encounters').select('*, diagnoses(*), prescriptions(*)').eq('patient_id', body.patientId).order('created_at', { ascending: false }).limit(5);
      const { data: vitals } = await supabase.from('vital_signs').select('*').eq('patient_id', body.patientId).order('recorded_at', { ascending: false }).limit(3);
      const { data: labs } = await supabase.from('lab_orders').select('*, lab_results(*)').eq('patient_id', body.patientId).order('created_at', { ascending: false }).limit(5);

      systemPrompt = 'You are a senior clinical AI generating a printable medical summary report. Use clear sections: Patient overview, Vitals, Recent encounters, Diagnoses, Lab findings, Treatment plan, Recommendations. Use markdown.';
      userPrompt = `Generate a comprehensive medical report.\n\nPATIENT:\n${JSON.stringify(patient)}\n\nVITALS:\n${JSON.stringify(vitals)}\n\nENCOUNTERS:\n${JSON.stringify(encounters)}\n\nLABS:\n${JSON.stringify(labs)}`;
    } else if (body.mode === 'recommend') {
      const { data: similar } = await supabase.from('ai_case_memory').select('*').eq('diagnosis', body.diagnosis).limit(20);
      systemPrompt = 'You are a clinical decision-support AI. Given a diagnosis and similar past cases, suggest 3 treatment options with rationale. Stay concise and practical. Use markdown.';
      userPrompt = `Diagnosis: ${body.diagnosis}\nContext: ${body.context ?? ''}\n\nPast similar cases (for reference):\n${JSON.stringify(similar)}`;
    } else if (body.mode === 'synthesize_protocol') {
      const { data: cases } = await supabase.from('ai_case_memory').select('*').eq('diagnosis', body.diagnosis).limit(50);
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
      await supabase.from('ai_protocols').insert({
        diagnosis: body.diagnosis, protocol_text: content, case_count: 0, status: 'pending_review',
      });
    }

    return new Response(JSON.stringify({ content }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
