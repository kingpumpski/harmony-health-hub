export type WorkflowSound =
  | 'success'
  | 'warning'
  | 'critical'
  | 'info'
  | 'document'
  | 'order'
  | 'result'
  | 'medication'
  | 'error';

let audioContext: AudioContext | null = null;

function getAudioContext() {
  if (typeof window === 'undefined') return null;
  try {
    audioContext ??= new AudioContext();
    if (audioContext.state === 'suspended') void audioContext.resume().catch(() => undefined);
    return audioContext;
  } catch {
    return null;
  }
}

/** Short, non-verbal UI feedback. Browsers may block background audio until the user has interacted with the site. */
export function playWorkflowSound(kind: WorkflowSound = 'success') {
  const ctx = getAudioContext();
  if (!ctx) return;

  const patterns: Record<WorkflowSound, number[]> = {
    success: [660, 880],
    info: [520],
    warning: [440, 330],
    critical: [880, 660, 880],
    document: [620, 740],
    order: [560, 700],
    result: [740, 980],
    medication: [500, 620, 500],
    error: [220, 180, 220],
  };
  const gainLevel: Record<WorkflowSound, number> = {
    success: 0.035,
    info: 0.025,
    warning: 0.04,
    critical: 0.055,
    document: 0.028,
    order: 0.03,
    result: 0.04,
    medication: 0.032,
    error: 0.04,
  };

  const now = ctx.currentTime;
  patterns[kind].forEach((frequency, index) => {
    const oscillator = ctx.createOscillator();
    const gain = ctx.createGain();
    oscillator.type = kind === 'critical' || kind === 'error' ? 'square' : 'sine';
    const start = now + index * 0.11;
    oscillator.frequency.setValueAtTime(frequency, start);
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(gainLevel[kind], start + 0.015);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.09);
    oscillator.connect(gain).connect(ctx.destination);
    oscillator.start(start);
    oscillator.stop(start + 0.1);
  });
}

export function notificationSoundKind(notification: {
  severity?: string | null;
  category?: string | null;
  title?: string | null;
}): WorkflowSound {
  const severity = String(notification.severity ?? '').toLowerCase();
  const category = String(notification.category ?? '').toLowerCase();
  const title = String(notification.title ?? '').toLowerCase();

  if (severity === 'critical') return 'critical';
  if (/result|approved|diagnostic/.test(title) || /result|diagnostic/.test(category)) return 'result';
  if (/medication|pharmacy|dose|mar/.test(title) || /medication|pharmacy/.test(category)) return 'medication';
  if (/lab|imaging|radiology|service|order/.test(title) || /lab|imaging|radiology|service|order/.test(category)) return 'order';
  if (/document|record|report/.test(title) || /document|record|report/.test(category)) return 'document';
  if (severity === 'warning' || severity === 'high') return 'warning';
  if (severity === 'success') return 'success';
  return 'info';
}
