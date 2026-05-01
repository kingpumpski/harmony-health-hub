import { useMemo, useState } from 'react';
import { Bell, Speaker, Zap, ShieldCheck, Music2, AlertTriangle } from 'lucide-react';

const soundConfigs = [
  { id: 'critical', label: 'Critical patient alarm', description: 'Triggers when a patient enters critical status.', category: 'critical' },
  { id: 'lab', label: 'Lab results ready', description: 'Alerts clinicians when lab results are available.', category: 'notification' },
  { id: 'medication', label: 'Medication reminder', description: 'Notifies nursing staff when a dose is due.', category: 'reminder' },
  { id: 'emergency', label: 'Emergency call sound', description: 'Used for urgent emergency alerts.', category: 'emergency' },
];

export default function SoundAlerts() {
  const [activeSound, setActiveSound] = useState<string | null>(null);
  const [logs, setLogs] = useState<string[]>([]);

  const playSound = (soundType: string) => {
    const audio = new Audio('data:audio/wav;base64,UklGRkoAAABXQVZFZm10IBAAAAABAAEAESsAACJWAAACABAAZGF0YQAAAAA=');
    audio.play().catch(() => {});
    setActiveSound(soundType);
    setLogs((prev) => [`${new Date().toLocaleTimeString()}: ${soundType} triggered`, ...prev].slice(0, 6));
  };

  const activeConfig = useMemo(() => soundConfigs.find((item) => item.id === activeSound), [activeSound]);

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Clinical Sound Alerts</h1>
          <p className="text-muted-foreground">Configure and trigger sound categories with visual notification support.</p>
        </div>
        <button className="btn-primary inline-flex items-center gap-2">
          <Bell className="w-4 h-4" /> Configure Sounds
        </button>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        {soundConfigs.map((config) => (
          <div key={config.id} className="card-medical p-6 rounded-3xl border border-border">
            <div className="flex items-center gap-3 mb-4">
              <Speaker className="w-5 h-5 text-primary" />
              <div>
                <h2 className="font-semibold">{config.label}</h2>
                <p className="text-sm text-muted-foreground">{config.description}</p>
              </div>
            </div>
            <button className="btn-secondary w-full" onClick={() => playSound(config.label)}>
              Trigger Sound
            </button>
          </div>
        ))}
      </div>

      <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
        <div className="card-medical p-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-semibold">Visual Notification Panel</h2>
              <p className="text-sm text-muted-foreground">Shows active alerts and audio triggers in one place.</p>
            </div>
            <Zap className="w-5 h-5 text-info" />
          </div>
          {activeConfig ? (
            <div className="rounded-3xl border border-border p-6 bg-background/60">
              <p className="text-sm text-muted-foreground">Last triggered:</p>
              <h3 className="mt-2 text-xl font-semibold">{activeConfig.label}</h3>
              <p className="mt-2">{activeConfig.description}</p>
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">Trigger a sound to display it here.</p>
          )}
        </div>

        <div className="card-medical p-6">
          <div className="flex items-center gap-3 mb-4">
            <Music2 className="w-5 h-5 text-success" />
            <div>
              <h2 className="text-lg font-semibold">Activity Log</h2>
              <p className="text-sm text-muted-foreground">Recent sound actions</p>
            </div>
          </div>
          <div className="space-y-3">
            {logs.length ? logs.map((log) => (
              <div key={log} className="rounded-2xl border border-border p-3 text-sm">{log}</div>
            )) : (
              <p className="text-sm text-muted-foreground">No sound events triggered yet.</p>
            )}
          </div>
        </div>
      </div>

      <div className="card-medical p-6 rounded-3xl border border-border bg-warning/10">
        <div className="flex items-center gap-3">
          <AlertTriangle className="w-5 h-5 text-warning" />
          <p className="text-sm text-warning">Sound alerts are critical for emergency response workflows. Each audio action also generates a visible notification for staff in the dashboard.</p>
        </div>
      </div>
    </div>
  );
}
