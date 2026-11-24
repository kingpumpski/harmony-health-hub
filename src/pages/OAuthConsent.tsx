import { useEffect, useState } from 'react';
import { Navigate, useLocation, useSearchParams } from 'react-router-dom';
import { ShieldCheck } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';

type Result<T> = Promise<{ data: T | null; error: { message: string } | null }>;
type Details = { client?: { name?: string; client_name?: string; redirect_uri?: string }; redirect_uri?: string; scope?: string; redirect_url?: string; redirect_to?: string };
type Redirect = { redirect_url?: string; redirect_to?: string };
type OAuthApi = {
  getAuthorizationDetails(id: string): Result<Details>;
  approveAuthorization(id: string): Result<Redirect>;
  denyAuthorization(id: string): Result<Redirect>;
};
const oauth = () => (supabase.auth as unknown as { oauth: OAuthApi }).oauth;

const scopeLabel = (s: string) =>
  s === 'openid' ? 'Confirm who you are' : s === 'email' ? 'Share your email address' : s === 'profile' ? 'Share your basic profile' : `Additional permission requested: ${s}`;

export default function OAuthConsent() {
  const [params] = useSearchParams();
  const location = useLocation();
  const { isAuthenticated, loading, user } = useAuth();
  const authorizationId = params.get('authorization_id');
  const [details, setDetails] = useState<Details | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!authorizationId || loading || !isAuthenticated) return;
    oauth().getAuthorizationDetails(authorizationId).then(({ data, error }) => {
      if (error || !data) return setError(error?.message ?? 'This connection request is invalid or has expired.');
      const redirect = data.redirect_url ?? data.redirect_to;
      if (redirect && !data.client) { window.location.href = redirect; return; }
      setDetails(data);
    }, () => setError('Could not load the connection request.'));
  }, [authorizationId, loading, isAuthenticated]);

  if (!authorizationId) return <Shell><p className="text-sm text-destructive">This connection link is missing its request ID.</p></Shell>;
  if (loading) return <Shell><p className="text-sm text-muted-foreground">Loading…</p></Shell>;
  if (!isAuthenticated) {
    const next = location.pathname + location.search;
    return <Navigate to={`/login?next=${encodeURIComponent(next)}`} replace />;
  }

  const decide = async (approve: boolean) => {
    setBusy(true); setError('');
    try {
      const { data, error } = approve ? await oauth().approveAuthorization(authorizationId) : await oauth().denyAuthorization(authorizationId);
      const redirect = data?.redirect_url ?? data?.redirect_to;
      if (error || !redirect) throw new Error(error?.message ?? 'No redirect returned.');
      window.location.href = redirect;
    } catch (e) {
      setError(`Could not ${approve ? 'approve' : 'cancel'} the connection: ${(e as Error).message}`);
      setBusy(false);
    }
  };

  const clientName = details?.client?.client_name ?? details?.client?.name ?? 'This app';
  const redirectUri = details?.client?.redirect_uri ?? details?.redirect_uri;
  const scopes = (details?.scope ?? '').split(/\s+/).filter(Boolean);

  return (
    <Shell>
      {!details && !error && <p className="text-sm text-muted-foreground">Loading connection request…</p>}
      {details && (
        <Card>
          <CardHeader>
            <ShieldCheck className="h-8 w-8 text-primary" />
            <CardTitle>Connect {clientName} to Harmony Health Hub</CardTitle>
            <CardDescription>Signed in as {user?.email ?? 'your account'}. This lets {clientName} use this app as you.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            {redirectUri && <p className="text-muted-foreground break-all">Returns to: {redirectUri}</p>}
            <p>{clientName} will be able to search patients and view upcoming appointments you already have access to.</p>
            {scopes.length > 0 && <ul className="list-disc pl-5">{scopes.map((s) => <li key={s}>{scopeLabel(s)}</li>)}</ul>}
            <p className="text-muted-foreground">This does not bypass this app's permissions or record access rules.</p>
          </CardContent>
          <CardFooter className="flex gap-2 justify-end">
            <Button variant="outline" disabled={busy} onClick={() => decide(false)}>Cancel connection</Button>
            <Button disabled={busy} onClick={() => decide(true)}>Approve</Button>
          </CardFooter>
        </Card>
      )}
      {error && <p role="alert" className="text-sm text-destructive mt-3">{error}</p>}
    </Shell>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return <div className="min-h-screen flex items-center justify-center bg-background p-4"><div className="w-full max-w-md">{children}</div></div>;
}
