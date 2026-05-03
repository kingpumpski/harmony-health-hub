import { corsHeaders } from '@supabase/supabase-js/cors';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

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
          { role: 'system', content: 'You analyze patient-uploaded outside diagnostics. Provide a brief clinical interpretation, flag urgent findings, and suggest next steps.' },
          { role: 'user', content: `Document type: ${documentType}\nTitle: ${title}\n\nProvide an interpretation and clinical next steps.` },
        ],
      }),
    });
    const data = await aiRes.json();
    const analysis = data.choices?.[0]?.message?.content ?? '';

    await supabase.from('outside_lab_documents').update({ ai_analysis: analysis, ai_analyzed_at: new Date().toISOString() }).eq('id', documentId);

    // Notify clinicians
    await supabase.from('notifications').insert({
      recipient_role: 'practitioner', title: 'New outside-lab document analyzed', message: title || 'A new external diagnostic was uploaded and analyzed.',
      severity: 'info', category: 'lab', related_entity_id: documentId, link: '/laboratory',
    });

    return new Response(JSON.stringify({ analysis }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
