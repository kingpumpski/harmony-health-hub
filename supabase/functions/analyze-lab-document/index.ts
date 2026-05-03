import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const { documentId, title, documentType } = await req.json();
    const apiKey = Deno.env.get('LOVABLE_API_KEY');
    if (!apiKey) throw new Error('LOVABLE_API_KEY missing');

    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    const aiRes = await fetch('https://ai.gateway.lovable.dev/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'google/gemini-2.5-flash',
        messages: [
          {
            role: 'system',
            content:
              'You analyze patient-uploaded outside diagnostics. Provide a brief clinical interpretation, flag urgent findings, and suggest next steps. ' +
              'If findings are urgent or critical, begin your response with the literal token "URGENT:" on the first line. Otherwise begin with "ROUTINE:".',
          },
          { role: 'user', content: `Document type: ${documentType}\nTitle: ${title}\n\nProvide an interpretation and clinical next steps.` },
        ],
      }),
    });

    if (!aiRes.ok) {
      const errText = await aiRes.text().catch(() => '');
      throw new Error(`AI gateway error ${aiRes.status}: ${errText}`);
    }

    const data = await aiRes.json();
    const analysis: string = data.choices?.[0]?.message?.content ?? '';
    const isUrgent = /^\s*URGENT:/i.test(analysis);

    // Look up patient for the notification target
    const { data: doc } = await supabase
      .from('outside_lab_documents')
      .select('patient_id')
      .eq('id', documentId)
      .maybeSingle();

    await supabase
      .from('outside_lab_documents')
      .update({ ai_analysis: analysis, ai_analyzed_at: new Date().toISOString() })
      .eq('id', documentId);

    // Broadcast to multiple clinical roles
    const roles = ['practitioner', 'nurse', 'lab_technician'];
    const severity = isUrgent ? 'critical' : 'info';
    const titleMsg = isUrgent ? '🚨 URGENT outside-lab finding' : 'New outside-lab document analyzed';
    const rows = roles.map((r) => ({
      recipient_role: r,
      title: titleMsg,
      message: `${title || 'Outside diagnostic'} (${documentType}) analyzed by AI.${isUrgent ? ' Review immediately.' : ''}`,
      severity,
      category: 'lab',
      related_entity_id: documentId,
      related_patient_id: doc?.patient_id ?? null,
      link: '/outside-lab',
    }));
    await supabase.from('notifications').insert(rows);

    return new Response(JSON.stringify({ analysis, urgent: isUrgent }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('[analyze-lab-document] error', e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
