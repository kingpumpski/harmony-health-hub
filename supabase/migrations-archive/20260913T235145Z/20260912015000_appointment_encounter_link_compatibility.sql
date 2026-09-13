-- Legacy deployments may contain multiple historical encounters for one appointment.
-- Keep the relationship indexed without making migration depend on historical uniqueness.
DROP INDEX IF EXISTS public.uq_encounters_appointment_id;

CREATE INDEX IF NOT EXISTS idx_encounters_appointment_id_lookup
  ON public.encounters(appointment_id);
