import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  const cors = buildCorsHeaders(req);
  try {
    const { patientEmail, patientName, testName } = await req.json();
    console.log(`[notify-lab-result] would email ${patientEmail} (${patientName}) about ${testName}`);
    return new Response(JSON.stringify({ queued: true, patientEmail, testName }), {
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } });
  }
});
