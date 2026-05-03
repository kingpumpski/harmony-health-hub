import { HeartPulse } from 'lucide-react';

export default function SplashScreen() {
  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-background">
      <div className="flex flex-col items-center gap-4">
        <div className="relative w-24 h-24 rounded-3xl bg-gradient-to-br from-primary to-accent flex items-center justify-center shadow-elevated animate-scale-in">
          <HeartPulse className="w-14 h-14 text-primary-foreground animate-[pulse-critical_1.2s_ease-in-out_infinite]" />
          <span className="absolute inset-0 rounded-3xl ring-4 ring-primary/30 animate-ping" />
        </div>
        <div className="text-center animate-fade-in">
          <h1 className="text-3xl font-heading font-bold tracking-tight">MediCare</h1>
          <p className="text-sm text-muted-foreground">Pro Health System</p>
        </div>
      </div>
    </div>
  );
}
