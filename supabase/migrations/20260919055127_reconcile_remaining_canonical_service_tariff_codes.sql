-- Canonical billing aliases referenced by reconciliation workflows.
-- Keep prices at zero until the facility imports/configures its approved tariff schedule.
INSERT INTO public.service_tariffs
  (service_code, service_name, department, unit, amount, active, currency, metadata)
VALUES
  ('WARD-ACCOM','Accommodation / detention','ward','day',0,true,'GHS',
   jsonb_build_object('canonical_alias_for','WARD-ACCOM','requires_facility_tariff_configuration',true)),
  ('MEAL','Patient feeding','feeding','meal',0,true,'GHS',
   jsonb_build_object('canonical_alias_for','MEAL','requires_facility_tariff_configuration',true)),
  ('PROCEDURE-GENERIC','Other medical service / procedure','procedure','service',0,true,'GHS',
   jsonb_build_object('canonical_alias_for','PROCEDURE','requires_facility_tariff_configuration',true))
ON CONFLICT (service_code) DO UPDATE
SET service_name=EXCLUDED.service_name,
    department=EXCLUDED.department,
    unit=EXCLUDED.unit,
    active=true,
    metadata=EXCLUDED.metadata,
    updated_at=now();