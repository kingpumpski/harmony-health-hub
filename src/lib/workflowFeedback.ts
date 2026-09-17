export type WorkflowSound = 'success' | 'warning' | 'critical' | 'info';

let audioContext: AudioContext | null = null;

function getAudioContext() {
  if (typeof window === 'undefined') return null;
  audioContext ??= new AudioContext();
  if (audioContext.state === 'suspended') void audioContext.resume();
  return audioContext;
}

/** Short, non-verbal UI feedback. Safe to call after a user action; browsers may block unsolicited background audio. */
export function playWorkflowSound(kind: WorkflowSound = 'success') {
  const ctx = getAudioContext();
  if (!ctx) return;

  const patterns: Record<WorkflowSound, number[]> = {
    success: [660, 880],
    info: [520],
    warning: [440, 330],
    critical: [880, 660, 880],
  };
  const gainLevel: Record<WorkflowSound, number> = {
    success: 0.035,
    info: 0.025,
    warning: 0.04,
    critical: 0.055,
  };

  const now = ctx.currentTime;
  patterns[kind].forEach((frequency, index) => {
    const oscillator = ctx.createOscillator();
    const gain = ctx.createGain();
    oscillator.type = kind === 'critical' ? 'square' : 'sine';
    oscillator.frequency.setValueAtTime(frequency, now + index * 0.11);
    gain.gain.setValueAtTime(0.0001, now + index * 0.11);
    gain.gain.exponentialRampToValueAtTime(gainLevel[kind], now + index * 0.11 + 0.015);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + index * 0.11 + 0.09);
    oscillator.connect(gain).connect(ctx.destination);
    oscillator.start(now + index * 0.11);
    oscillator.stop(now + index * 0.11 + 0.1);
  });
}
