import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { Loader2, MailCheck, TriangleAlert } from 'lucide-react';

export default function AuthCallback() {
  const navigate = useNavigate();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;

    const completeAuth = async () => {
      const params = new URLSearchParams(window.location.search);
      const code = params.get('code');
      const errorDescription = params.get('error_description');

      if (errorDescription) {
        if (mounted) setError(errorDescription);
        return;
      }

      if (code) {
        const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code);
        if (exchangeError) {
          if (mounted) setError(exchangeError.message);
          return;
        }
      }

      const { data, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) {
        if (mounted) setError(sessionError.message);
        return;
      }

      if (!data.session) {
        if (mounted) setError('The confirmation link is invalid, expired, or has already been used.');
        return;
      }

      navigate('/dashboard', { replace: true });
    };

    void completeAuth();
    return () => { mounted = false; };
  }, [navigate]);

  if (error) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background p-6">
        <div className="card-medical w-full max-w-md p-8 text-center">
          <TriangleAlert className="mx-auto h-10 w-10 text-destructive" />
          <h1 className="mt-4 text-xl font-semibold">Email confirmation failed</h1>
          <p className="mt-2 text-sm text-muted-foreground">{error}</p>
          <button type="button" onClick={() => navigate('/login', { replace: true })} className="btn-primary mt-6 w-full">
            Return to sign in
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-background p-6">
      <div className="card-medical w-full max-w-md p-8 text-center">
        <MailCheck className="mx-auto h-10 w-10 text-primary" />
        <h1 className="mt-4 text-xl font-semibold">Confirming your email…</h1>
        <p className="mt-2 text-sm text-muted-foreground">Please wait while we securely activate your account.</p>
        <Loader2 className="mx-auto mt-6 h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    </div>
  );
}
