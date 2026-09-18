import { searchPatientDirectory } from '@/lib/patientDirectory';
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { Upload, FileText, Sparkles } from 'lucide-react';
import { playSuccessSound } from '@/lib/sounds';

interface Doc { id: string; patient_id: string; document_type: string; title: string; storage_path: string; ai_analysis: string | null; created_at: string }

export default function OutsideLabUploads() {
  const [docs, setDocs] = useState<Doc[]>([]);
  const [patients, setPatients] = useState<any[]>([]);
  const [pid, setPid] = useState('');
  const [type, setType] = useState('X-ray');
  const [title, setTitle] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);

  const load = async () => {
    const { data, error } = await supabase.from('outside_lab_documents').select('*').order('created_at', { ascending: false }).limit(50);
    if (error) {
      toast({ title: 'Unable to load outside-lab documents', description: error.message, variant: 'destructive' });
      return;
    }
    setDocs((data ?? []) as Doc[]);
  };

  useEffect(() => {
    void load();
    searchPatientDirectory('', 200).then(({ data }) => setPatients(data ?? []));
  }, []);

  const upload = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!file || !pid) return toast({ title: 'Patient and file required', variant: 'destructive' });
    setBusy(true);
    let uploadedPath: string | null = null;
    try {
      const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
      const path = `${pid}/${crypto.randomUUID()}-${safeName}`;
      uploadedPath = path;
      const { error: upErr } = await supabase.storage.from('outside-lab').upload(path, file, { upsert: false });
      if (upErr) throw upErr;

      const { data: doc, error: dErr } = await (supabase as any).rpc('register_outside_lab_document', {
        _patient_id: pid,
        _document_type: type,
        _title: title || file.name,
        _storage_path: path,
        _mime_type: file.type || null,
      });
      if (dErr) throw dErr;

      void supabase.functions.invoke('analyze-lab-document', {
        body: { documentId: doc.id, title: title || file.name, documentType: type },
      });

      playSuccessSound();
      toast({
        title: '✓ Upload successful',
        description: 'Document uploaded. AI analysis is running and clinicians will be notified.',
      });
      setFile(null); setTitle(''); setPid('');
      void load();
    } catch (err: any) {
      if (uploadedPath) {
        await supabase.storage.from('outside-lab').remove([uploadedPath]);
      }
      toast({ title: 'Upload failed', description: err?.message ?? 'Unable to register document', variant: 'destructive' });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Upload className="w-6 h-6 text-primary" /> Outside Lab Uploads</h1>
        <p className="text-muted-foreground">Upload external X-rays, scans, ECGs, PDFs. AI analyzes and notifies clinicians.</p>
      </div>

      <form onSubmit={upload} className="card-medical p-6 grid md:grid-cols-2 gap-3">
        <select value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical">
          <option value="">Select patient…</option>
          {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}
        </select>
        <select value={type} onChange={(e) => setType(e.target.value)} className="input-medical">
          <option>X-ray</option><option>CT scan</option><option>MRI</option><option>Ultrasound</option>
          <option>ECG</option><option>Lab report (PDF)</option><option>Other</option>
        </select>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Title (optional)" className="input-medical md:col-span-2" />
        <input type="file" onChange={(e) => setFile(e.target.files?.[0] ?? null)} className="input-medical md:col-span-2" />
        <button disabled={busy} className="btn-primary md:col-span-2">{busy ? 'Uploading…' : 'Upload & analyze'}</button>
      </form>

      <div className="card-medical p-5">
        <h2 className="font-semibold mb-3">Recent uploads</h2>
        <div className="space-y-3">
          {docs.map((d) => (
            <div key={d.id} className="rounded-xl border border-border p-4">
              <div className="flex flex-col gap-2 sm:flex-row sm:justify-between sm:items-start text-sm">
                <span className="font-medium flex items-center gap-2 min-w-0"><FileText className="w-4 h-4 shrink-0" /> <span className="truncate">{d.title}</span> <span className="text-muted-foreground shrink-0">· {d.document_type}</span></span>
                <span className="text-muted-foreground shrink-0">{new Date(d.created_at).toLocaleString()}</span>
              </div>
              {d.ai_analysis ? (
                <div className="mt-2 text-xs bg-primary/5 border border-primary/20 rounded p-3">
                  <p className="flex items-center gap-1 font-medium text-primary mb-1"><Sparkles className="w-3 h-3" /> AI analysis</p>
                  <p className="whitespace-pre-wrap">{d.ai_analysis}</p>
                </div>
              ) : (
                <p className="text-xs text-muted-foreground mt-2">Awaiting AI analysis…</p>
              )}
            </div>
          ))}
          {docs.length === 0 && <p className="text-sm text-muted-foreground">No uploads yet.</p>}
        </div>
      </div>
    </div>
  );
}
