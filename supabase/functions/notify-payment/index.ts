import { corsHeaders } from '@supabase/supabase-js/cors';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const { invoiceId, amount, patientId } = await req.json();
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    // Broadcast in-app notifications
    await supabase.from('notifications').insert([
      { recipient_role: 'accountant', title: 'Payment received', message: `Payment of GHS ${amount} recorded for invoice ${invoiceId}`, severity: 'success', category: 'payment', related_patient_id: patientId, related_entity_id: invoiceId, link: '/billing' },
    ]);

    console.log(`[notify-payment] queued for invoice ${invoiceId}`);
    return new Response(JSON.stringify({ ok: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
