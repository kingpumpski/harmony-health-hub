import { useState, useRef, useEffect } from 'react';
import { searchDiagnosisTerms, searchTerms, type DiagnosisSuggestion } from '@/lib/medicalTerms';
import { supabase } from '@/integrations/supabase/client';
import { Mic, MicOff } from 'lucide-react';

interface Props {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  className?: string;
  enableVoice?: boolean;
  multiline?: boolean;
  diagnosisOnly?: boolean;
  onDiagnosisSelect?: (suggestion: DiagnosisSuggestion) => void;
}

export default function MedicalTermInput({ value, onChange, placeholder, className, enableVoice = true, multiline, diagnosisOnly = false, onDiagnosisSelect }: Props) {
  const [open, setOpen] = useState(false);
  const [recording, setRecording] = useState(false);
  const [catalogue, setCatalogue] = useState<DiagnosisSuggestion[]>([]);
  const recognitionRef = useRef<any>(null);
  const localSuggestions = diagnosisOnly ? searchDiagnosisTerms(value) : searchTerms(value).map((label) => ({ label, code: '', source: 'ICD-10' as const }));
  const suggestions = diagnosisOnly
    ? (catalogue.length > 0 ? catalogue : localSuggestions).filter((item) => `${item.code} ${item.label}`.toLowerCase().includes(value.trim().toLowerCase())).slice(0, 10)
    : localSuggestions;

  useEffect(() => {
    if (!diagnosisOnly || value.trim().length < 2) return;
    let active = true;
    const timer = window.setTimeout(async () => {
      const term = value.trim();
      const [{ data: icd }, { data: stg }] = await Promise.all([
        supabase.from('icd_codes').select('code,description,version').or(`code.ilike.%${term}%,description.ilike.%${term}%`).limit(8),
        supabase.from('stg_guidelines').select('icd_code,condition').or(`icd_code.ilike.%${term}%,condition.ilike.%${term}%`).limit(8),
      ]);
      if (!active) return;
      const results: DiagnosisSuggestion[] = [
        ...(icd ?? []).map((item) => ({ label: item.description, code: item.code, source: 'ICD-10' as const })),
        ...(stg ?? []).map((item) => ({ label: item.condition, code: item.icd_code ?? '', source: 'STG-Ghana' as const })),
      ];
      setCatalogue(Array.from(new Map(results.map((item) => [`${item.code}:${item.label}`, item])).values()));
    }, 180);
    return () => { active = false; window.clearTimeout(timer); };
  }, [diagnosisOnly, value]);

  useEffect(() => {
    const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (SR) {
      const rec = new SR();
      rec.continuous = true;
      rec.interimResults = false;
      rec.lang = 'en-US';
      rec.onresult = (ev: any) => {
        const txt = Array.from(ev.results).map((r: any) => r[0].transcript).join(' ');
        onChange((value ? value + ' ' : '') + txt);
      };
      rec.onend = () => setRecording(false);
      recognitionRef.current = rec;
    }
  }, []);

  const toggleVoice = () => {
    const rec = recognitionRef.current;
    if (!rec) return;
    if (recording) { rec.stop(); setRecording(false); } else { rec.start(); setRecording(true); }
  };

  const InputEl = multiline ? 'textarea' : 'input';
  return (
    <div className="relative">
      <InputEl
        value={value}
        onChange={(e: any) => { onChange(e.target.value); setOpen(true); }}
        onBlur={() => setTimeout(() => setOpen(false), 150)}
        onFocus={() => setOpen(true)}
        placeholder={placeholder}
        className={`input-medical w-full ${enableVoice ? 'pr-10' : ''} ${className ?? ''}`}
        rows={multiline ? 3 : undefined}
      />
      {enableVoice && recognitionRef.current && (
        <button type="button" onClick={toggleVoice} className={`absolute right-2 top-2 p-1.5 rounded-md transition ${recording ? 'bg-critical/20 text-critical animate-pulse' : 'text-muted-foreground hover:text-foreground'}`} title="Speech to text">
          {recording ? <MicOff className="w-4 h-4" /> : <Mic className="w-4 h-4" />}
        </button>
      )}
      {open && suggestions.length > 0 && (
        <div className="absolute z-10 mt-1 w-full bg-popover border border-border rounded-lg shadow-lg max-h-60 overflow-auto">
            {suggestions.map(s => (
            <button key={`${s.code}-${s.label}`} type="button" onMouseDown={(e) => { e.preventDefault(); onChange(diagnosisOnly && s.code ? `${s.label} [${s.code}]` : s.label); onDiagnosisSelect?.(s); setOpen(false); }} className="w-full text-left px-3 py-2 text-sm hover:bg-accent">
              <span className="block">{s.label}</span>
              {diagnosisOnly && <span className="text-xs text-muted-foreground">{s.source}{s.code ? ` · ${s.code}` : ''}</span>}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
