import { useEffect, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

export type ClinicalReference = {
  id: string;
  parameter: string;
  population_scope: string;
  source_name: string;
  source_reference: string;
  source_url: string;
  source_is_ghana_specific: boolean;
  effective_date: string;
  normal_min: number | null;
  normal_max: number | null;
  thresholds: Record<string, unknown>;
  display_text: string;
  last_reviewed_at: string;
  review_due_at: string;
  is_active: boolean;
};

export function useClinicalReferences(parameters: string[]) {
  const [references, setReferences] = useState<ClinicalReference[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const parameterKey = parameters.join('|');

  useEffect(() => {
    let active = true;
    const load = async () => {
      setLoading(true);
      setError(null);
      const { data, error } = await (supabase as any)
        .from('clinical_reference_values')
        .select('id,parameter,population_scope,source_name,source_reference,source_url,source_is_ghana_specific,effective_date,normal_min,normal_max,thresholds,display_text,last_reviewed_at,review_due_at,is_active')
        .in('parameter', parameters)
        .eq('is_active', true)
         .eq('population_scope', 'adult');
      if (active) {
        if (error) setError(error.message);
        setReferences((data ?? []) as ClinicalReference[]);
        setLoading(false);
      }
    };
    void load();
    return () => { active = false; };
  }, [parameterKey]);

  const byParameter = useMemo(
    () => new Map(references.map((reference) => [reference.parameter, reference])),
    [references],
  );

  return { references, byParameter, loading, error };
}

export function formatReferenceHelper(reference: ClinicalReference | undefined) {
  if (!reference) return null;
  return {
    text: reference.display_text,
    source: reference.source_name,
    sourceReference: reference.source_reference,
    sourceUrl: reference.source_url,
  };
}
