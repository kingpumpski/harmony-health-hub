import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { AlertTriangle, X } from 'lucide-react';

interface Alert {
  id: string;
  patient_id: string;
  details: string;
  severity: string;
  created_at: string;
}

const beep = () => {
  try {
    const ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
    const o = ctx.createOscillator(); const g = ctx.createGain();
    o.connect(g); g.connect(ctx.destination);
    o.frequency.value = 880; o.type = 'square';
    g.gain.setValueAtTime(0.15, ctx.currentTime);
    o.start(); o.stop(ctx.currentTime + 0.4);
    setTimeout(() => {
      const o2 = ctx.createOscillator(); const g2 = ctx.createGain();
      o2.connect(g2); g2.connect(ctx.destination);
      o2.frequency.value = 660; o2.type = 'square';
      g2.gain.setValueAtTime(0.15, ctx.currentTime);
      o2.start(); o2.stop(ctx.currentTime + 0.4);
    }, 500);
  } catch {}
};

const CLINICAL_ROLES = ['practitioner','nurse','midwife','admin'];

export default function CriticalAlertOverlay() {
  const { user } = useAuth();
  const [alerts, setAlerts] = useState<Alert[]>([]);

  useEffect(() => {
    if (!user || !CLINICAL_ROLES.includes(user.role)) return;
    const ch = supabase.channel('vital-alerts')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'vital_alerts' }, (payload) => {
        const a = payload.new as Alert;
        if (a.severity === 'critical') {
          setAlerts((prev) => [a, ...prev].slice(0, 3));
          beep();
        }
      })
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [user]);

  const dismiss = async (id: string) => {
    await supabase.rpc('acknowledge_vital_alert', { _alert_id: id });
    setAlerts((prev) => prev.filter(a => a.id !== id));
  };

  if (!alerts.length) return null;

  return (
    <div className="pointer-events-none fixed bottom-4 right-4 z-40 flex max-h-[min(60vh,28rem)] w-[min(24rem,calc(100vw-2rem))] flex-col gap-2 overflow-y-auto">
      {alerts.map(a => (
        <div key={a.id} className="pointer-events-auto rounded-xl border-2 border-critical bg-critical text-critical-foreground p-4 shadow-elevated animate-scale-in pulse-critical">
          <div className="flex items-start justify-between gap-2">
            <div className="flex items-start gap-2">
              <AlertTriangle className="w-5 h-5 shrink-0 mt-0.5" />
              <div>
                <p className="font-bold">CRITICAL VITAL ALERT</p>
                <p className="text-sm opacity-95">{a.details}</p>
                <p className="text-xs opacity-80 mt-1">{new Date(a.created_at).toLocaleTimeString()}</p>
              </div>
            </div>
            <button onClick={() => dismiss(a.id)} className="text-critical-foreground/80 hover:text-critical-foreground">
              <X className="w-4 h-4" />
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}
