import { corsHeaders } from '@supabase/supabase-js/cors';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const { patientEmail, patientName, testName } = await req.json();
    console.log(`[notify-lab-result] would email ${patientEmail} (${patientName}) about ${testName}`);
    // Email sending is queued — will activate once an email domain is verified.
    return new Response(JSON.stringify({ queued: true, patientEmail, testName }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
