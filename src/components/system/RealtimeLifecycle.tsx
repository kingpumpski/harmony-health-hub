import { useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';

/**
 * Browsers may suspend WebSockets while a page is stored in the
 * Back-Forward Cache. Reconnect Supabase Realtime on a persisted restore
 * so active subscriptions can rejoin and live clinical alerts resume.
 */
export default function RealtimeLifecycle() {
  useEffect(() => {
    const handlePageShow = (event: PageTransitionEvent) => {
      if (!event.persisted) return;
      try {
        supabase.realtime.disconnect();
        supabase.realtime.connect();
      } catch (error) {
        console.warn('[realtime] reconnect after BFCache restore failed:', error);
      }
    };
    window.addEventListener('pageshow', handlePageShow);
    return () => window.removeEventListener('pageshow', handlePageShow);
  }, []);

  return null;
}
