import { useEffect, useRef, useState } from 'react';
import { Eraser, Save, PenLine } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';

export default function SignaturePad() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const drawingRef = useRef(false);
  const [savedSignature, setSavedSignature] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const load = async () => {
      const { data, error } = await supabase
        .from('staff_signatures')
        .select('signature_data')
        .order('updated_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!error && data?.signature_data) setSavedSignature(data.signature_data);
    };
    void load();
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ratio = Math.max(1, window.devicePixelRatio || 1);
    const rect = canvas.getBoundingClientRect();
    canvas.width = Math.floor(rect.width * ratio);
    canvas.height = Math.floor(rect.height * ratio);
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.scale(ratio, ratio);
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = '#111827';
  }, []);

  const point = (event: React.PointerEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return null;
    const rect = canvas.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  };

  const start = (event: React.PointerEvent<HTMLCanvasElement>) => {
    const p = point(event);
    if (!p) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    drawingRef.current = true;
    const ctx = canvasRef.current?.getContext('2d');
    ctx?.beginPath();
    ctx?.moveTo(p.x, p.y);
  };

  const move = (event: React.PointerEvent<HTMLCanvasElement>) => {
    if (!drawingRef.current) return;
    const p = point(event);
    if (!p) return;
    const ctx = canvasRef.current?.getContext('2d');
    ctx?.lineTo(p.x, p.y);
    ctx?.stroke();
  };

  const end = () => { drawingRef.current = false; };

  const clear = () => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
  };

  const save = async () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const data = canvas.toDataURL('image/png');
    if (!data || data.length < 100) {
      toast({ title: 'Draw your signature first', variant: 'destructive' });
      return;
    }
    setSaving(true);
    const { data: saved, error } = await supabase.rpc('upsert_my_staff_signature', { _signature_data: data });
    setSaving(false);
    if (error) return toast({ title: 'Signature save failed', description: error.message, variant: 'destructive' });
    setSavedSignature((saved as any)?.signature_data ?? data);
    clear();
    toast({ title: 'Signature saved', description: 'Your signature will be available for authorized laboratory report documents.' });
  };

  return <section className="card-medical rounded-3xl p-6 space-y-4">
    <div><h2 className="font-semibold flex items-center gap-2"><PenLine className="h-5 w-5 text-primary" /> Laboratory report signature</h2><p className="text-sm text-muted-foreground mt-1">Lab technicians can save an individual signature once. Authorized laboratory printouts can embed the saved signature.</p></div>
    <div className="rounded-2xl border border-dashed border-border bg-background overflow-hidden">
      <canvas ref={canvasRef} className="block h-40 w-full touch-none cursor-crosshair" onPointerDown={start} onPointerMove={move} onPointerUp={end} onPointerCancel={end} aria-label="Draw your laboratory report signature" />
    </div>
    <div className="flex flex-wrap gap-2">
      <button type="button" onClick={clear} className="btn-secondary inline-flex items-center gap-2"><Eraser className="h-4 w-4" /> Clear</button>
      <button type="button" onClick={() => void save()} disabled={saving} className="btn-primary inline-flex items-center gap-2"><Save className="h-4 w-4" /> {saving ? 'Saving…' : 'Save signature'}</button>
    </div>
    {savedSignature && <div className="rounded-2xl border border-border bg-white p-4"><p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Saved signature</p><img src={savedSignature} alt="Saved laboratory report signature" className="h-20 max-w-full object-contain" /></div>}
  </section>;
}
