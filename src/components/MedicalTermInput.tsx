import { useEffect, useRef, useState } from 'react';
import { searchTerms } from '@/lib/medicalTerms';
import { supabase } from '@/integrations/supabase/client';
import { Mic, MicOff } from 'lucide-react';

export interface DiagnosisSuggestion {
  label: string;
  code: string;
  source: string;
}

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

export default function MedicalTermInput({
  value,
  onChange,
  placeholder,
  className,
  enableVoice = true,
  multiline,
  diagnosisOnly = false,
  onDiagnosisSelect,
}: Props) {
  const [open, setOpen] = useState(false);
  const [recording, setRecording] = useState(false);
  const [remoteSuggestions, setRemoteSuggestions] = useState<DiagnosisSuggestion[]>([]);
  const [searchError, setSearchError] = useState<string | null>(null);
  const recognitionRef = useRef<any>(null);
  const localSuggestions = diagnosisOnly ? [] : searchTerms(value, 8);

  useEffect(() => {
    const term = value.trim();
    if (term.length < 2) {
      setRemoteSuggestions([]);
      setSearchError(null);
      return;
    }

    let cancelled = false;
    const timer = window.setTimeout(async () => {
      const { data, error } = await supabase.rpc('search_clinical_diagnoses', {
        _query: term,
        _facility_id: null,
        _limit: 12,
      });

      if (cancelled) return;

      if (error) {
        setRemoteSuggestions([]);
        setSearchError(error.message);
        return;
      }

      setSearchError(null);
      const rows = (data ?? []) as Array<{
        display_name?: string | null;
        code?: string | null;
        source?: string | null;
        standard_name?: string | null;
        icd10_code?: string | null;
      }>;

      setRemoteSuggestions(
        rows
          .map((row) => ({
            label: row.display_name?.trim() ?? '',
            code: row.code ?? row.icd10_code ?? '',
            source: row.standard_name ?? row.source ?? 'Clinical diagnosis',
          }))
          .filter((row) => row.label),
      );
    }, 180);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [value, diagnosisOnly]);

  useEffect(() => {
    const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SR) return;

    const rec = new SR();
    rec.continuous = true;
    rec.interimResults = false;
    rec.lang = 'en-US';
    rec.onresult = (ev: any) => {
      const txt = Array.from(ev.results).map((r: any) => r[0].transcript).join(' ');
      onChange((value ? value + ' ' : '') + txt);
    };
    rec.onend = () => setRecording(false);
    rec.onerror = () => setRecording(false);
    recognitionRef.current = rec;

    return () => {
      try { rec.stop(); } catch { /* recognition may already be stopped */ }
      recognitionRef.current = null;
    };
  }, []);

  const toggleVoice = () => {
    const rec = recognitionRef.current;
    if (!rec) return;
    if (recording) {
      rec.stop();
      setRecording(false);
    } else {
      try {
        rec.start();
        setRecording(true);
      } catch {
        setRecording(false);
      }
    }
  };

  const remoteLabels = new Set(remoteSuggestions.map((item) => item.label.toLowerCase()));
  const suggestions: DiagnosisSuggestion[] = [
    ...remoteSuggestions,
    ...localSuggestions
      .filter((item) => !remoteLabels.has(item.toLowerCase()))
      .map((item) => ({ label: item, code: '', source: 'Clinical terms' })),
  ].slice(0, 12);

  const selectSuggestion = (suggestion: DiagnosisSuggestion) => {
    onChange(suggestion.label);
    onDiagnosisSelect?.(suggestion);
    setOpen(false);
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
        aria-autocomplete="list"
        aria-expanded={open && suggestions.length > 0}
      />
      {enableVoice && recognitionRef.current && (
        <button
          type="button"
          onClick={toggleVoice}
          className={`absolute right-2 top-2 p-1.5 rounded-md transition ${recording ? 'bg-critical/20 text-critical animate-pulse' : 'text-muted-foreground hover:text-foreground'}`}
          title="Speech to text"
          aria-label={recording ? 'Stop speech to text' : 'Start speech to text'}
        >
          {recording ? <MicOff className="w-4 h-4" /> : <Mic className="w-4 h-4" />}
        </button>
      )}
      {open && suggestions.length > 0 && (
        <div className="absolute z-10 mt-1 w-full bg-popover border border-border rounded-lg shadow-lg max-h-60 overflow-auto" role="listbox">
          {suggestions.map((s, index) => (
            <button
              key={`${s.source}-${s.code}-${s.label}-${index}`}
              type="button"
              role="option"
              onMouseDown={(e) => { e.preventDefault(); selectSuggestion(s); }}
              className="w-full text-left px-3 py-2 text-sm hover:bg-accent"
            >
              <span className="block">{s.label}</span>
              {(s.code || s.source) && <span className="block text-xs text-muted-foreground">{s.code}{s.code && s.source ? ' · ' : ''}{s.source}</span>}
            </button>
          ))}
        </div>
      )}
      {searchError && diagnosisOnly && value.trim().length >= 2 && (
        <p className="mt-1 text-xs text-muted-foreground" role="status">
          Diagnosis catalogue search is temporarily unavailable. You can continue entering the diagnosis manually.
        </p>
      )}
    </div>
  );
}
