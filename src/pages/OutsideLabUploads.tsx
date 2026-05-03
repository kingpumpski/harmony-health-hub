import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { Upload, FileText, Sparkles } from 'lucide-react';

interface Doc { id: string; patient_id: string; document_type: string; title: string; storage_path: string; ai_analysis: string | null; created_at: string }

export default function OutsideLabUploads() {
  const { user } = useAuth();
  const [docs, setDocs] = useState<Doc[]>([]);
  const [patients, setPatients] = useState<any[]>([]);
  const [pid, setPid] = useState('');
  const [type, setType] = useState('X-ray');
  const [title, setTitle] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);

  const load = async () => {
    const { data } = await supabase.from('outside_lab_documents').select('*').order('created_at', { ascending: false }).limit(50);
    setDocs((data ?? []) as Doc[]);
  };

  useEffect(() => {
    load();
    supabase.from('patients').select('id, first_name, last_name').limit(200).then(({ data }) => setPatients(data ?? []));
  }, []);

  const upload = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!file || !pid) return toast({ title: 'Patient and file required', variant: 'destructive' });
    setBusy(true);
    try {
      const path = `${pid}/${Date.now()}-${file.name}`;
      const { error: upErr } = await supabase.storage.from('outside-lab').upload(path, file);
      if (upErr) throw upErr;
      const { data: doc, error: dErr } = await supabase.from('outside_lab_documents').insert({
        patient_id: pid, document_type: type, title: title || file.name,
        storage_path: path, mime_type: file.type, uploaded_by: user?.id,
      }).select().single();
      if (dErr) throw dErr;

      // Trigger AI analysis (best-effort)
      supabase.functions.invoke('analyze-lab-document', { body: { documentId: doc.id, title: title || file.name, documentType: type } });

      toast({ title: 'Uploaded', description: 'AI analysis in progress…' });
      setFile(null); setTitle(''); setPid('');
      load();
    } catch (err: any) {
      toast({ title: 'Upload failed', description: err.message, variant: 'destructive' });
    }
    setBusy(false);
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
              <div className="flex justify-between text-sm">
                <span className="font-medium flex items-center gap-2"><FileText className="w-4 h-4" /> {d.title} <span className="text-muted-foreground">· {d.document_type}</span></span>
                <span className="text-muted-foreground">{new Date(d.created_at).toLocaleString()}</span>
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
