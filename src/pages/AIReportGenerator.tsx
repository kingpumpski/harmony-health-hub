import { searchPatientDirectory } from '@/lib/patientDirectory';
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { Sparkles, FileText, Printer, Volume2 } from 'lucide-react';

export default function AIReportGenerator() {
  const [patients, setPatients] = useState<any[]>([]);
  const [pid, setPid] = useState('');
  const [content, setContent] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    searchPatientDirectory('', 200).then(({ data }) => setPatients(data ?? []));
  }, []);

  const generate = async () => {
    if (!pid) return;
    setBusy(true); setContent('');
    const { data, error } = await supabase.functions.invoke('ai-clinical-assist', {
      body: { mode: 'report', patientId: pid },
    });
    setBusy(false);
    if (error || data?.error) return toast({ title: 'Failed', description: data?.error ?? error?.message, variant: 'destructive' });
    setContent(data.content);
  };

  const speak = () => {
    if (!content) return;
    const u = new SpeechSynthesisUtterance(content.replace(/[#*_`]/g, ''));
    u.rate = 1.0;
    speechSynthesis.cancel();
    speechSynthesis.speak(u);
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="text-2xl font-heading font-bold flex items-center gap-2"><Sparkles className="w-6 h-6 text-primary" /> AI Report Generator</h1>
        <p className="text-muted-foreground">Generate printable medical summaries from full patient history, vitals, encounters, and labs.</p>
      </div>

      <div className="card-medical p-6 space-y-3">
        <div className="flex flex-wrap gap-3">
          <select value={pid} onChange={(e) => setPid(e.target.value)} className="input-medical flex-1 min-w-[240px]">
            <option value="">Select patient…</option>
            {patients.map((p) => <option key={p.id} value={p.id}>{p.first_name} {p.last_name}</option>)}
          </select>
          <button onClick={generate} disabled={busy || !pid} className="btn-primary inline-flex items-center gap-2">
            <Sparkles className="w-4 h-4" /> {busy ? 'Generating…' : 'Generate report'}
          </button>
          {content && (
            <>
              <button onClick={() => window.print()} className="btn-ghost inline-flex items-center gap-2"><Printer className="w-4 h-4" /> Print</button>
              <button onClick={speak} className="btn-ghost inline-flex items-center gap-2"><Volume2 className="w-4 h-4" /> Read aloud</button>
            </>
          )}
        </div>

        {content && (
          <div className="prose prose-sm max-w-none mt-4 print:prose-base">
            <div className="card-medical p-6 whitespace-pre-wrap font-body" id="report-content">
              <div className="flex items-center gap-2 mb-4 not-prose">
                <FileText className="w-5 h-5 text-primary" />
                <h2 className="text-xl font-heading font-bold">Medical Report</h2>
              </div>
              {content}
            </div>
          </div>
        )}
        {!content && !busy && <p className="text-sm text-muted-foreground">Pick a patient and generate to see the report.</p>}
      </div>
    </div>
  );
}
