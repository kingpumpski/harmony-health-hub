// Trusted background worker for in-app + external notification delivery.
// Reconciled onto the current main notification onboarding baseline.
// Provider credentials are server-side environment variables only.
// Supported channels: in_app, email (Resend), sms/whatsapp (Twilio), push (signed webhook).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

const BATCH = 25;
const BACKOFF_SECONDS = [10, 30, 120, 600, 3600];

type QueueRow = {
  id: string;
  channel: string;
  payload: Record<string, unknown>;
  attempts: number;
  max_attempts: number;
};

const json = (body: unknown, status = 200, headers: Record<string,string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { ...headers, 'Content-Type': 'application/json' } });

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function sendResend(to: string, subject: string, message: string, link?: string | null) {
  const key = Deno.env.get('RESEND_API_KEY');
  const from = Deno.env.get('RESEND_FROM_EMAIL');
  if (!key || !from) throw new Error('Email provider is not configured');
  const html = '<p>' + message.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('\n','<br>') +
    (link ? '<p><a href="' + link.replaceAll('"','&quot;') + '">Open notification</a></p>' : '');
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from, to: [to], subject, html, text: message + (link ? `\n\nOpen notification: ${link}` : '') }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`Email provider returned ${response.status}`);
  return String(body.id ?? '');
}

async function sendTwilio(to: string, body: string, whatsapp: boolean) {
  const sid = Deno.env.get('TWILIO_ACCOUNT_SID');
  const token = Deno.env.get('TWILIO_AUTH_TOKEN');
  const from = whatsapp ? Deno.env.get('TWILIO_WHATSAPP_FROM') : Deno.env.get('TWILIO_FROM_NUMBER');
  if (!sid || !token || !from) throw new Error(`${whatsapp ? 'WhatsApp' : 'SMS'} provider is not configured`);
  const destination = whatsapp ? `whatsapp:${to}` : to;
  const sender = whatsapp ? (from.startsWith('whatsapp:') ? from : `whatsapp:${from}`) : from;
  const params = new URLSearchParams({ To: destination, From: sender, Body: body });
  const auth = btoa(`${sid}:${token}`);
  const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
    method: 'POST',
    headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params,
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`Twilio returned ${response.status}`);
  return String(result.sid ?? '');
}

async function sendPush(subscription: Record<string, unknown>, payload: Record<string, unknown>) {
  const endpoint = Deno.env.get('NOTIFICATION_PUSH_WEBHOOK_URL');
  const secret = Deno.env.get('NOTIFICATION_PUSH_WEBHOOK_SECRET');
  if (!endpoint || !secret) throw new Error('Push provider is not configured');
  const body = JSON.stringify({ subscription, payload });
  const signature = await crypto.subtle.sign(
    'HMAC',
    await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']),
    new TextEncoder().encode(body),
  );
  const hex = Array.from(new Uint8Array(signature)).map((b) => b.toString(16).padStart(2, '0')).join('');
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Harmony-Signature': `sha256=${hex}` },
    body,
  });
  if (!response.ok) throw new Error(`Push provider returned ${response.status}`);
  const result = await response.json().catch(() => ({}));
  return String(result.message_id ?? result.id ?? '');
}

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  const cors = buildCorsHeaders(req);
  const authHeader = req.headers.get('Authorization') ?? '';
  const expected = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!expected || !authHeader.startsWith('Bearer ') || authHeader.slice(7) !== expected) {
    return json({ error: 'Worker authentication required' }, 401, cors);
  }

  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, expected);
  const { data: due, error: pullErr } = await supabase.rpc('claim_notification_queue', { _limit: BATCH });
  if (pullErr) return json({ error: 'Notification queue claim failed' }, 500, cors);

  let delivered = 0, failed = 0;
  for (const row of (due ?? []) as QueueRow[]) {
    const attempts = (row.attempts ?? 0) + 1;
    try {
      const p = row.payload ?? {};
      const channel = String(row.channel);
      const notificationId = String(p.notification_id ?? '');
      if (channel === 'in_app') {
        if (notificationId) {
          const { data: notification, error } = await supabase.from('notifications').select('id,recipient_role,recipient_user_id,title,message,severity,category,link,related_patient_id,related_entity_id,metadata').eq('id', notificationId).maybeSingle();
          if (error || !notification) throw new Error('Notification record not found');
          const { error: insertError } = await supabase.from('notifications').insert({ recipient_role: notification.recipient_role, recipient_user_id: notification.recipient_user_id, title: notification.title, message: notification.message, severity: notification.severity, category: notification.category, link: notification.link, related_patient_id: notification.related_patient_id, related_entity_id: notification.related_entity_id, metadata: notification.metadata ?? {}, source_queue_id: row.id });
          if (insertError && insertError.code !== '23505') throw insertError;
        } else {
          const { error: insertError } = await supabase.from('notifications').insert({
            recipient_role: p.recipient_role ?? null,
            recipient_user_id: p.recipient_user_id ?? null,
            title: p.title,
            message: p.message,
            severity: p.severity ?? 'info',
            category: p.category ?? 'other',
            link: p.link ?? null,
            related_patient_id: p.related_patient_id ?? null,
            related_entity_id: p.related_entity_id ?? null,
            metadata: p.metadata ?? {},
            source_queue_id: row.id,
          });
          if (insertError && insertError.code !== '23505') throw insertError;
        }
      } else {
        if (!notificationId) throw new Error('External notification queue row has no notification_id');
        const { data: n, error: nErr } = await supabase.from('notifications').select('id,title,message,severity,category,link,metadata').eq('id', notificationId).maybeSingle();
        if (nErr || !n) throw new Error('Notification record not found');

        const userId = String(p.recipient_user_id ?? '');
        if (!userId) throw new Error('External notification has no recipient user');
        const [{ data: profile }, { data: subscriptions }, { data: preference }] = await Promise.all([
          supabase.from('profiles').select('email,phone').eq('id', userId).maybeSingle(),
          channel === 'push' ? supabase.from('notification_push_subscriptions').select('subscription').eq('user_id', userId) : Promise.resolve({ data: [] }),
          supabase.from('notification_channel_preferences').select('allow_clinical_content').eq('user_id', userId).maybeSingle(),
        ]);

        let provider = channel;
        let providerMessageId = '';
        const clinicalCategory = /^(lab|encounter|triage|prescription|admission|telemedicine|result|clinical)$/i.test(String(n.category ?? ''));
        const safeMessage = clinicalCategory && preference?.allow_clinical_content !== true
          ? 'You have a clinical notification in Harmony Health Hub. Sign in to review the protected details.'
          : n.message;
        const message = `[${String(n.severity).toUpperCase()}] ${n.title}: ${safeMessage}${n.link ? `\n${n.link}` : ''}`;

        if (channel === 'email') {
          const destination = profile?.email;
          if (!destination) throw new Error('Recipient email is unavailable');
          provider = 'resend';
          providerMessageId = await sendResend(destination, n.title, safeMessage, n.link);
          await supabase.from('notification_deliveries').upsert({ queue_id: row.id, user_id: userId, channel, provider, destination_hash: await sha256(destination.toLowerCase()), status: 'delivered', attempts, provider_message_id: providerMessageId || null, delivered_at: new Date().toISOString(), last_error: null }, { onConflict: 'queue_id,user_id,channel' });
        } else if (channel === 'sms' || channel === 'whatsapp') {
          const destination = profile?.phone;
          if (!destination) throw new Error('Recipient phone is unavailable');
          provider = 'twilio';
          providerMessageId = await sendTwilio(destination, message, channel === 'whatsapp');
          await supabase.from('notification_deliveries').upsert({ queue_id: row.id, user_id: userId, channel, provider, destination_hash: await sha256(destination), status: 'delivered', attempts, provider_message_id: providerMessageId || null, delivered_at: new Date().toISOString(), last_error: null }, { onConflict: 'queue_id,user_id,channel' });
        } else if (channel === 'push') {
          const rows = (subscriptions ?? []) as Array<{ subscription: Record<string, unknown> }>;
          if (!rows.length) throw new Error('Recipient has no push subscription');
          provider = 'push-webhook';
          for (const subscription of rows) {
            providerMessageId = await sendPush(subscription.subscription, { id: n.id, title: n.title, message: safeMessage, severity: n.severity, category: n.category, link: n.link, metadata: n.metadata });
          }
          await supabase.from('notification_deliveries').upsert({ queue_id: row.id, user_id: userId, channel, provider, destination_hash: await sha256(JSON.stringify(rows.map((s) => s.subscription))), status: 'delivered', attempts, provider_message_id: providerMessageId || null, delivered_at: new Date().toISOString(), last_error: null }, { onConflict: 'queue_id,user_id,channel' });
        } else {
          throw new Error(`Unsupported notification channel: ${channel}`);
        }
      }

      await supabase.from('notification_queue').update({ status: 'delivered', attempts, delivered_at: new Date().toISOString(), last_error: null }).eq('id', row.id).eq('status', 'processing');
      delivered++;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const max = row.max_attempts ?? 5;
      const isFinal = attempts >= max;
      const backoff = BACKOFF_SECONDS[Math.min(attempts - 1, BACKOFF_SECONDS.length - 1)];
      await supabase.from('notification_deliveries').upsert({
        queue_id: row.id,
        user_id: typeof row.payload?.recipient_user_id === 'string' ? row.payload.recipient_user_id : null,
        channel: row.channel,
        provider: row.channel === 'email' ? 'resend' : row.channel === 'sms' || row.channel === 'whatsapp' ? 'twilio' : row.channel,
        status: isFinal ? 'failed' : 'pending',
        attempts,
        last_error: msg.slice(0, 500),
      }, { onConflict: 'queue_id,user_id,channel' });
      await supabase.from('notification_queue').update({ status: isFinal ? 'failed' : 'pending', attempts, last_error: msg.slice(0, 500), next_attempt_at: new Date(Date.now() + backoff * 1000).toISOString() }).eq('id', row.id).eq('status', 'processing');
      failed++;
    }
  }

  return json({ checked: due?.length ?? 0, delivered, failed }, 200, cors);
});
