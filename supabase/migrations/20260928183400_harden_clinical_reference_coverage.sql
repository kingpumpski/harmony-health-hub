-- Extend the clinical reference catalogue to cover calculated BMI and the
-- measurement inputs that feed it. These are guidance references, not diagnostic rules.

INSERT INTO public.clinical_reference_values
(parameter, population_scope, source_name, source_reference, source_url, source_is_ghana_specific, effective_date, normal_min, normal_max, thresholds, display_text, last_reviewed_at, review_due_at)
VALUES
('body_mass_index','adult','World Health Organization (WHO)','Nutrition for a healthy life – WHO recommendations','https://www.who.int/europe/news-room/fact-sheets/item/nutrition---maintaining-a-healthy-lifestyle',false,'2025-07-18',18.5,24.9,'{"underweight_max":18.5,"overweight_min":25,"obesity_min":30}','Adult BMI is calculated as weight in kilograms divided by height in metres squared. WHO adult categories: <18.5 underweight; 18.5–24.9 normal; ≥25 overweight; ≥30 obesity.','2026-09-28T00:00:00Z','2028-09-28T00:00:00Z'),
('weight_measurement','adult','World Health Organization (WHO)','Obesity and overweight','https://www.who.int/news-room/fact-sheets/detail/obesity-and-overweight',false,'2025-12-08',NULL,NULL,'{}','Record measured body weight in kilograms. Adult weight and height measurements are used to calculate BMI; interpretation depends on age and clinical context.','2026-09-28T00:00:00Z','2028-09-28T00:00:00Z'),
('height_measurement','adult','World Health Organization (WHO)','Obesity and overweight','https://www.who.int/news-room/fact-sheets/detail/obesity-and-overweight',false,'2025-12-08',NULL,NULL,'{}','Record measured body height in metres. Adult height and weight measurements are used to calculate BMI; interpretation depends on age and clinical context.','2026-09-28T00:00:00Z','2028-09-28T00:00:00Z')
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
