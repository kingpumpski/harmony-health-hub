-- Reconcile canonical service tariff codes used by billing reconciliation workflows.
-- Facility-specific prices are intentionally not assigned here.

BEGIN;

INSERT INTO public.service_tariffs
  (service_code,service_name,department,unit,amount,active,source_standard,effective_from,effective_to,currency,metadata)
SELECT
  'LAB-GENERIC', service_name, department, unit, amount, active,
  source_standard, effective_from, effective_to, currency,
  COALESCE(metadata,'{}'::jsonb) || jsonb_build_object('canonical_alias_for','LAB')
FROM public.service_tariffs
WHERE service_code='LAB'
ON CONFLICT (service_code) DO NOTHING;

INSERT INTO public.service_tariffs
  (service_code,service_name,department,unit,amount,active,source_standard,effective_from,effective_to,currency,metadata)
SELECT
  'IMAGING-GENERIC','Diagnostic imaging','Imaging','examination',0,true,
  NULL,NULL,NULL,'GHS',
  jsonb_build_object('canonical_alias_for','IMAGING','requires_facility_tariff_configuration',true)
WHERE NOT EXISTS (
  SELECT 1 FROM public.service_tariffs WHERE service_code='IMAGING-GENERIC'
);

COMMIT;
