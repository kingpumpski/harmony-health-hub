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
    if (authError || !user) throw new Error('Authentication required');
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: profile } = await db.from('profiles').select('role').eq('id', user.id).maybeSingle();
    const allowedRoles = ['admin','practitioner','nurse','midwife','specialist_nurse','radiologist','lab_technician'];
    if (!allowedRoles.includes(String(profile?.role ?? ''))) return new Response(JSON.stringify({ error: 'Forbidden' }), { status: 403, headers: { ...cors, 'Content-Type': 'application/json' } });
    const { documentId, title, documentType } = await req.json();
    if (!documentId) throw new Error('Document id is required');
    const apiKey = Deno.env.get('LOVABLE_API_KEY');
    if (!apiKey) throw new Error('LOVABLE_API_KEY missing');
    const { data: doc, error: docError } = await db.from('outside_lab_documents').select('patient_id,title,document_type').eq('id', documentId).maybeSingle();
    if (docError || !doc) throw new Error('Document not found');
    const effectiveTitle = String(title ?? doc.title ?? 'Outside diagnostic').slice(0, 300);
    const effectiveType = String(documentType ?? doc.document_type ?? 'diagnostic').slice(0, 100);
    const aiRes = await fetch('https://ai.gateway.lovable.dev/v1/chat/completions', { method: 'POST', headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ model: 'google/gemini-2.5-flash', messages: [{ role: 'system', content: 'You analyze patient-uploaded outside diagnostics. Provide a brief clinical interpretation, flag urgent findings, and suggest next steps. If findings are urgent or critical, begin your response with the literal token "URGENT:" on the first line. Otherwise begin with "ROUTINE:".' }, { role: 'user', content: `Document type: ${effectiveType}\\nTitle: ${effectiveTitle}\\n\\nProvide an interpretation and clinical next steps.` }] }) });
    if (!aiRes.ok) throw new Error(`AI gateway error ${aiRes.status}: ${await aiRes.text().catch(() => '')}`);
    const data = await aiRes.json();
    const analysis = String(data.choices?.[0]?.message?.content ?? '');
    const isUrgent = /^\\s*URGENT:/i.test(analysis);
    await db.from('outside_lab_documents').update({ ai_analysis: analysis, ai_analyzed_at: new Date().toISOString() }).eq('id', documentId);
    const roles = ['practitioner', 'nurse', 'lab_technician'];
    const severity = isUrgent ? 'critical' : 'info';
    const titleMsg = isUrgent ? '🚨 URGENT outside-lab finding' : 'New outside-lab document analyzed';
    const queueRows = roles.map((r) => ({ channel: 'in_app', payload: { recipient_role: r, title: titleMsg, message: `${effectiveTitle} (${effectiveType}) analyzed by AI.${isUrgent ? ' Review immediately.' : ''}`, severity, category: 'lab', related_entity_id: documentId, related_patient_id: doc.patient_id, link: '/outside-lab' } }));
    await db.from('notification_queue').insert(queueRows);
    await db.from('notifications').insert(roles.map((r) => ({ recipient_role: r, title: titleMsg, message: `${effectiveTitle} (${effectiveType}) analyzed by AI.${isUrgent ? ' Review immediately.' : ''}`, severity, category: 'lab', related_entity_id: documentId, related_patient_id: doc.patient_id, link: '/outside-lab' })));
    return new Response(JSON.stringify({ analysis, urgent: isUrgent, queued: queueRows.length }), { headers: { ...cors, 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } });
  }
});
