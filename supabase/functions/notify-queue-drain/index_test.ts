// Smoke test: verifies the outside-lab notification flow.
// Inserts a notification_queue row simulating an urgent finding, drains the queue,
// and asserts that a critical lab notification appears for the practitioner role.
import 'https://deno.land/std@0.224.0/dotenv/load.ts';
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const SUPABASE_URL = Deno.env.get('VITE_SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

Deno.test({
  name: 'outside-lab urgent finding produces critical notification',
  ignore: !SERVICE_ROLE,
  fn: async () => {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE!);
    const marker = `smoketest-${crypto.randomUUID()}`;

    const { error: qErr } = await supabase.from('notification_queue').insert({
      channel: 'in_app',
      payload: {
        recipient_role: 'practitioner',
        title: '🚨 URGENT outside-lab finding',
        message: `${marker} – urgent CT finding`,
        severity: 'critical',
        category: 'lab',
        link: '/outside-lab',
      },
    });
    assertEquals(qErr, null);

    const drainRes = await fetch(`${SUPABASE_URL}/functions/v1/notify-queue-drain`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${SERVICE_ROLE}`, 'Content-Type': 'application/json' },
      body: '{}',
    });
    const drainBody = await drainRes.json();
    assert(drainRes.ok, `drain failed: ${JSON.stringify(drainBody)}`);

    const { data: notifs } = await supabase
      .from('notifications')
      .select('*')
      .ilike('message', `%${marker}%`)
      .limit(5);

    assert((notifs?.length ?? 0) > 0, 'expected delivered notification');
    const n = notifs![0];
    assertEquals(n.severity, 'critical');
    assertEquals(n.recipient_role, 'practitioner');
    assertEquals(n.category, 'lab');

    // Cleanup
    await supabase.from('notifications').delete().ilike('message', `%${marker}%`);
    await supabase.from('notification_queue').delete().ilike('payload->>message', `%${marker}%`);
  },
});
