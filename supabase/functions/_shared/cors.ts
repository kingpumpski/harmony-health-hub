// Shared CORS helper for all edge functions.
// Reads ALLOWED_ORIGINS env (comma-separated). Falls back to allowing
// *.lovable.app + localhost. Always echoes the matched origin (never `*`)
// so credentials work and the policy is tight.

const FALLBACK_PATTERNS: RegExp[] = [
  /^https?:\/\/localhost(:\d+)?$/,
  /^https?:\/\/127\.0\.0\.1(:\d+)?$/,
  /^https:\/\/([a-z0-9-]+\.)*lovable\.app$/i,
  /^https:\/\/([a-z0-9-]+\.)*lovableproject\.com$/i,
];

function configuredOrigins(): string[] {
  const raw = Deno.env.get('ALLOWED_ORIGINS') ?? '';
  return raw.split(',').map((s) => s.trim()).filter(Boolean);
}

function isAllowed(origin: string | null): boolean {
  if (!origin) return false;
  const list = configuredOrigins();
  if (list.includes('*')) return true;
  if (list.includes(origin)) return true;
  return FALLBACK_PATTERNS.some((re) => re.test(origin));
}

export function buildCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin');
  const allowed = isAllowed(origin) ? origin! : '';
  return {
    'Access-Control-Allow-Origin': allowed,
    'Vary': 'Origin',
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Max-Age': '86400',
  };
}

export function handlePreflight(req: Request): Response | null {
  if (req.method !== 'OPTIONS') return null;
  return new Response('ok', { headers: buildCorsHeaders(req) });
}
