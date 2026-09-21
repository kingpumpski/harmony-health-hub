import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  const cors = buildCorsHeaders(req);
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return new Response(JSON.stringify({ error: 'Authentication required' }), { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } });
    const token = authHeader.replace(/^Bearer\s+/i, '');
    const authClient = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data: { user }, error: authError } = await authClient.auth.getUser(token);
    if (authError || !user) return new Response(JSON.stringify({ error: 'Authentication required' }), { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } });
    const { invoiceId, amount, patientId } = await req.json();
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: profile } = await db.from('profiles').select('role').eq('id', user.id).maybeSingle();
    if (!['admin','accountant','front_desk'].includes(String(profile?.role ?? ''))) return new Response(JSON.stringify({ error: 'Forbidden' }), { status: 403, headers: { ...cors, 'Content-Type': 'application/json' } });
    const numericAmount = Number(amount);
    if (!invoiceId || !patientId || !Number.isFinite(numericAmount) || numericAmount <= 0) throw new Error('Invalid payment notification');
    const { data: invoice, error: invoiceError } = await db.from('invoices').select('id,patient_id,total_amount').eq('id', invoiceId).maybeSingle();
    if (invoiceError || !invoice || invoice.patient_id !== patientId) throw new Error('Invoice/patient mismatch');
    if (numericAmount > Number(invoice.total_amount)) throw new Error('Payment amount exceeds invoice total');
    await db.from('notifications').insert([{ recipient_role: 'accountant', title: 'Payment received', message: `Payment of GHS ${numericAmount} recorded for invoice ${invoiceId}`, severity: 'success', category: 'payment', related_patient_id: patientId, related_entity_id: invoiceId, link: '/billing' }]);
    return new Response(JSON.stringify({ ok: true }), { headers: { ...cors, 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } });
  }
});
