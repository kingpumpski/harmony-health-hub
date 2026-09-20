// Drain the notification_queue with retry + exponential backoff.
// Triggered by pg_cron every minute (or by the client immediately after enqueue).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

const BATCH = 25;
const BACKOFF_SECONDS = [10, 30, 120, 600, 3600]; // attempts 1..5+

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  const cors = buildCorsHeaders(req);
  const authHeader = req.headers.get('Authorization') ?? '';
  const expected = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!expected || !authHeader.startsWith('Bearer ') || authHeader.slice(7) !== expected) return new Response(JSON.stringify({ error: 'Worker authentication required' }), { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: due, error: pullErr } = await supabase.rpc('claim_notification_queue', { _limit: BATCH });

  let delivered = 0, failed = 0;

  for (const row of due ?? []) {
    const attempts = (row.attempts ?? 0) + 1;
    try {
      // Currently we only support in_app channel (email queued for when domain is set up).
      const p = row.payload ?? {};
      const insertRow = {
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
      };
      const { error } = await supabase.from('notifications').insert(insertRow);
      if (error && error.code !== '23505') throw error;

      await supabase.from('notification_queue').update({
        status: 'delivered',
        attempts,
        delivered_at: new Date().toISOString(),
        last_error: null,
      }).eq('id', row.id).eq('status', 'processing');
      delivered++;
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      const max = row.max_attempts ?? 5;
      const isFinal = attempts >= max;
      const backoff = BACKOFF_SECONDS[Math.min(attempts - 1, BACKOFF_SECONDS.length - 1)];
      const next = new Date(Date.now() + backoff * 1000).toISOString();

      await supabase.from('notification_queue').update({
        status: isFinal ? 'failed' : 'pending',
        attempts,
        last_error: msg.slice(0, 500),
        next_attempt_at: next,
      }).eq('id', row.id).eq('status', 'processing');
      failed++;
    }
  }

  return new Response(JSON.stringify({ checked: due?.length ?? 0, delivered, failed }), {
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
});
