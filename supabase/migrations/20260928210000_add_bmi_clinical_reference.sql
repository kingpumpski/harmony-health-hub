-- Add a dedicated sourced BMI interpretation reference so the calculated BMI
-- card does not reuse a weight-measurement reference as a proxy.
INSERT INTO public.clinical_reference_values
(parameter, population_scope, source_name, source_reference, source_url, source_is_ghana_specific, effective_date, normal_min, normal_max, thresholds, display_text, last_reviewed_at, review_due_at)
VALUES
(
  'bmi_adult_interpretation',
  'adult',
  'World Health Organization (WHO)',
  'Body mass index (BMI) / Global Health Observatory',
  'https://www.who.int/data/gho/data/themes/topics/GHO/body-mass-index',
  false,
  '2026-09-28',
  18.5,
  24.9,
  '{"underweight":"<18.5","normal":"18.5–24.9","overweight":">=25","obesity":">=30","population_note":"Adult categories; do not apply to children or adolescents."}'::jsonb,
  'Adult BMI interpretation: <18.5 underweight; 18.5–24.9 normal weight; ≥25 overweight; ≥30 obesity. These categories are for adults and should not be applied to children or adolescents.',
  '2026-09-28T00:00:00Z',
  '2028-09-28T00:00:00Z'
)
ON CONFLICT (parameter, population_scope) WHERE is_active DO UPDATE SET
  source_name=excluded.source_name,
  source_reference=excluded.source_reference,
  source_url=excluded.source_url,
  source_is_ghana_specific=excluded.source_is_ghana_specific,
  effective_date=excluded.effective_date,
  normal_min=excluded.normal_min,
  normal_max=excluded.normal_max,
  thresholds=excluded.thresholds,
  display_text=excluded.display_text,
  last_reviewed_at=excluded.last_reviewed_at,
  review_due_at=excluded.review_due_at,
  updated_at=now();
