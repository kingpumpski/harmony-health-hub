// Lightweight in-app sound helpers (no asset downloads).
function createUserActivatedAudioContext(): AudioContext | null {
  if (typeof window === 'undefined') return null;
  if (typeof navigator !== 'undefined' && navigator.userActivation && !navigator.userActivation.hasBeenActive) return null;
  try {
    const AudioContextCtor = window.AudioContext || (window as any).webkitAudioContext;
    if (!AudioContextCtor) return null;
    const ctx = new AudioContextCtor();
    if (ctx.state === 'suspended') void ctx.resume().catch(() => undefined);
    return ctx;
  } catch {
    return null;
  }
}

export function playSuccessSound() {
  const ctx = createUserActivatedAudioContext();
  if (!ctx) return;
  try {
    const now = ctx.currentTime;
    const notes = [880, 1175];
    notes.forEach((freq, i) => {
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.type = 'sine';
      o.frequency.value = freq;
      o.connect(g);
      g.connect(ctx.destination);
      g.gain.setValueAtTime(0.0001, now + i * 0.12);
      g.gain.exponentialRampToValueAtTime(0.18, now + i * 0.12 + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, now + i * 0.12 + 0.18);
      o.start(now + i * 0.12);
      o.stop(now + i * 0.12 + 0.2);
    });
  } catch {
    try { void ctx.close(); } catch {}
  }
}

export function playAlertSound() {
  const ctx = createUserActivatedAudioContext();
  if (!ctx) return;
  try {
    const now = ctx.currentTime;
    [660, 660, 880].forEach((freq, i) => {
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.type = 'square';
      o.frequency.value = freq;
      o.connect(g);
      g.connect(ctx.destination);
      g.gain.setValueAtTime(0.0001, now + i * 0.18);
      g.gain.exponentialRampToValueAtTime(0.2, now + i * 0.18 + 0.16);
      o.start(now + i * 0.18);
      o.stop(now + i * 0.18 + 0.2);
    });
  } catch {
    try { void ctx.close(); } catch {}
  }
}
