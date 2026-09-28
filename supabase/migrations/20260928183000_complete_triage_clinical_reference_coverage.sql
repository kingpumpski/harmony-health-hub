-- Complete triage measurement helper coverage for weight and height.
-- Weight and height do not have a single universal adult "normal" value;
-- they are measured inputs used to calculate BMI. The helper therefore gives
-- measurement guidance and a sourced BMI interpretation without inventing a
-- normal weight or height range.

INSERT INTO public.clinical_reference_values
(parameter, population_scope, source_name, source_reference, source_url, source_is_ghana_specific, effective_date, normal_min, normal_max, thresholds, display_text, last_reviewed_at, review_due_at)
VALUES
(
  'weight_measurement',
  'adult',
  'World Health Organization (WHO)',
  'Body mass index (BMI) / Global Health Observatory',
  'https://www.who.int/data/gho/data/themes/topics/GHO/body-mass-index',
  false,
  '2026-09-28',
  NULL,
  NULL,
  '{"measurement_unit":"kg","bmi_formula":"weight_kg / (height_m ^ 2)"}'::jsonb,
  'Measure and record weight in kilograms. Adult BMI is calculated from measured weight and height; BMI 18.5–24.9 is the WHO normal-weight range, while <18.5 is underweight, ≥25 is overweight and ≥30 is obesity.',
  '2026-09-28T00:00:00Z',
  '2028-09-28T00:00:00Z'
),
(
  'height_measurement',
  'adult',
  'World Health Organization (WHO)',
  'Body mass index (BMI) / Global Health Observatory',
  'https://www.who.int/data/gho/data/themes/topics/GHO/body-mass-index',
  false,
  '2026-09-28',
  NULL,
  NULL,
  '{"measurement_unit":"m","bmi_formula":"weight_kg / (height_m ^ 2)"}'::jsonb,
  'Measure and record height in metres. Adult BMI is calculated as weight in kilograms divided by height in metres squared; BMI interpretation is age-specific and these adult categories should not be applied to children or adolescents.',
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
  updated_at=now();
