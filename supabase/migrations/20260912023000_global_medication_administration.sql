-- Medication administration record (MAR) foundation. Prescription linkage is UUID-only
-- because legacy prescription schemas differ across deployments.
CREATE TABLE IF NOT EXISTS public.medication_administrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  prescription_id UUID,
  medication_name TEXT NOT NULL,
  dose TEXT,
  route TEXT,
  scheduled_at TIMESTAMPTZ,
  administered_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','administered','held','refused','omitted','cancelled')),
  reason TEXT,
  administered_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  witnessed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The May schema already created this table with legacy names (drug_name,
-- inventory_id, quantity_dispensed) and without scheduled_at/status. CREATE TABLE
-- IF NOT EXISTS does not reconcile that existing table, so add canonical columns
-- before any indexes or later workflow functions use them.
ALTER TABLE public.medication_administrations
  ADD COLUMN IF NOT EXISTS medication_name TEXT,
  ADD COLUMN IF NOT EXISTS route TEXT,
  ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'scheduled',
  ADD COLUMN IF NOT EXISTS reason TEXT,
  ADD COLUMN IF NOT EXISTS witnessed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Preserve legacy drug labels and administration timestamps where available.
DO $mar_legacy_columns$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='medication_administrations' AND column_name='drug_name'
  ) THEN
    EXECUTE 'UPDATE public.medication_administrations SET medication_name = COALESCE(medication_name, drug_name) WHERE medication_name IS NULL';
  END IF;
END
$mar_legacy_columns$;

UPDATE public.medication_administrations
SET medication_name = COALESCE(medication_name, 'Unspecified medication'),
    scheduled_at = COALESCE(scheduled_at, administered_at, created_at),
    status = CASE
      WHEN status = 'scheduled' AND administered_at IS NOT NULL THEN 'administered'
      ELSE status
    END,
    updated_at = COALESCE(updated_at, created_at, now())
WHERE medication_name IS NULL OR scheduled_at IS NULL OR updated_at IS NULL
   OR (status = 'scheduled' AND administered_at IS NOT NULL);

ALTER TABLE public.medication_administrations
  ALTER COLUMN medication_name SET NOT NULL,
  ALTER COLUMN prescription_id DROP NOT NULL,
  ALTER COLUMN administered_at DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_mar_patient_time ON public.medication_administrations(patient_id, scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_mar_status_time ON public.medication_administrations(status, scheduled_at);
ALTER TABLE public.medication_administrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mar clinical access" ON public.medication_administrations;
CREATE POLICY "mar clinical access" ON public.medication_administrations FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'pharmacist')) WITH CHECK (administered_by IS NULL OR administered_by = auth.uid() OR public.has_role(auth.uid(),'admin'));
CREATE OR REPLACE FUNCTION public.touch_mar_updated_at() RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public AS $$ BEGIN NEW.updated_at=now(); RETURN NEW; END; $$;
DROP TRIGGER IF EXISTS t_mar_updated_at ON public.medication_administrations;
CREATE TRIGGER t_mar_updated_at BEFORE UPDATE ON public.medication_administrations FOR EACH ROW EXECUTE FUNCTION public.touch_mar_updated_at();
