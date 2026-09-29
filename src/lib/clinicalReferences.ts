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
};

export function useClinicalReferences(parameters: string[]) {
  const [references, setReferences] = useState<ClinicalReference[]>([]);
  const [loading, setLoading] = useState(true);
  const parameterKey = parameters.join('|');
  const parameterList = parameterKey ? parameterKey.split('|') : [];

  useEffect(() => {
    let active = true;
    const load = async () => {
      setLoading(true);
      const { data } = await (supabase as any)
        .from('clinical_reference_values')
        .select('id,parameter,population_scope,source_name,source_reference,source_url,source_is_ghana_specific,effective_date,normal_min,normal_max,thresholds,display_text,last_reviewed_at,review_due_at')
         .in('parameter', parameterList)
        .eq('is_active', true)
        .in('population_scope', ['adult', 'all_ages']);
      if (active) {
        const rows = (data ?? []) as ClinicalReference[];
        const preferred = parameterList.flatMap((parameter) => {
          const adult = rows.find((reference) => reference.parameter === parameter && reference.population_scope === 'adult');
          const allAges = rows.find((reference) => reference.parameter === parameter && reference.population_scope === 'all_ages');
          return adult ? [adult] : allAges ? [allAges] : [];
        });
        setReferences(preferred);
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

  return { references, byParameter, loading };
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
