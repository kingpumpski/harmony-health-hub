-- Facility default: clinical care is not blocked at every step by payment.
-- Accounts remains responsible for financial reconciliation/release where configured.
ALTER TABLE public.facility_configuration
  ALTER COLUMN routing_mode SET DEFAULT 'streamlined';
UPDATE public.facility_configuration
SET routing_mode='streamlined',
    updated_at=now()
WHERE routing_mode='pay_before_each_step';

ALTER TABLE public.facility_settings
  ALTER COLUMN payment_flow SET DEFAULT 'streamlined';
UPDATE public.facility_settings
SET payment_flow='streamlined',
    updated_at=now()
WHERE payment_flow='strict';
