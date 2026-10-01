-- Support joins and referential checks for medication-alert acknowledgements.
CREATE INDEX IF NOT EXISTS idx_medication_administrations_alert_acknowledged_by
  ON public.medication_administrations (alert_acknowledged_by);
