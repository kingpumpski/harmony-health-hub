-- Daily coverage activation for insured patients and partnered-company staff.
-- Activation is explicit, auditable, and never creates a permanent payment bypass.

ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS partner_company TEXT,
  ADD COLUMN IF NOT EXISTS partner_member_number TEXT;

CREATE TABLE IF NOT EXISTS public.patient_visit_authorizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  authorization_date DATE NOT NULL DEFAULT CURRENT_DATE,
  coverage_type TEXT NOT NULL CHECK (coverage_type IN ('insurance', 'partner_company')),
  payer_name TEXT NOT NULL,
  activated_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  activation_source TEXT NOT NULL CHECK (activation_source IN ('appointment', 'accounts')),
  appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (patient_id, authorization_date)
);

CREATE INDEX IF NOT EXISTS idx_patient_visit_authorizations_active
  ON public.patient_visit_authorizations(patient_id, authorization_date, active);

ALTER TABLE public.patient_visit_authorizations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff read visit authorizations" ON public.patient_visit_authorizations;
CREATE POLICY "staff read visit authorizations" ON public.patient_visit_authorizations
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'accountant')
    OR public.has_role(auth.uid(), 'front_desk')
    OR public.is_clinical_staff(auth.uid())
    OR EXISTS (SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid())
  );

CREATE OR REPLACE FUNCTION public.patient_coverage_details(_patient_id UUID)
RETURNS TABLE(coverage_type TEXT, payer_name TEXT)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT CASE
           WHEN NULLIF(trim(p.insurance_provider), '') IS NOT NULL THEN 'insurance'
           WHEN NULLIF(trim(p.partner_company), '') IS NOT NULL THEN 'partner_company'
         END,
         COALESCE(NULLIF(trim(p.insurance_provider), ''), NULLIF(trim(p.partner_company), ''))
  FROM public.patients p
  WHERE p.id = _patient_id
    AND (NULLIF(trim(p.insurance_provider), '') IS NOT NULL OR NULLIF(trim(p.partner_company), '') IS NOT NULL)
    AND (p.insurance_expiry IS NULL OR p.insurance_expiry >= CURRENT_DATE);
$$;

CREATE OR REPLACE FUNCTION public.activate_patient_visit_coverage(
  _patient_id UUID,
  _source TEXT,
  _appointment_id UUID DEFAULT NULL,
  _authorization_date DATE DEFAULT CURRENT_DATE
)
RETURNS public.patient_visit_authorizations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  coverage RECORD;
  result public.patient_visit_authorizations;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _source NOT IN ('appointment', 'accounts') THEN RAISE EXCEPTION 'Invalid activation source'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'accountant')
    OR public.has_role(auth.uid(), 'front_desk')
    OR public.is_clinical_staff(auth.uid())
  ) THEN RAISE EXCEPTION 'Only authorised staff can activate visit coverage'; END IF;

  SELECT * INTO coverage FROM public.patient_coverage_details(_patient_id);
  IF coverage.coverage_type IS NULL THEN
    RAISE EXCEPTION 'Patient has no active insurance or partnered-company coverage';
  END IF;
  IF _appointment_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.appointments WHERE id = _appointment_id AND patient_id = _patient_id
  ) THEN
    RAISE EXCEPTION 'Appointment does not belong to this patient';
  END IF;

  INSERT INTO public.patient_visit_authorizations(
    patient_id, authorization_date, coverage_type, payer_name,
    activated_by, activation_source, appointment_id, active
  )
  VALUES (
    _patient_id, _authorization_date, coverage.coverage_type, coverage.payer_name,
    auth.uid(), _source, _appointment_id, true
  )
  ON CONFLICT (patient_id, authorization_date) DO UPDATE SET
    coverage_type = EXCLUDED.coverage_type,
    payer_name = EXCLUDED.payer_name,
    activated_by = EXCLUDED.activated_by,
    activation_source = EXCLUDED.activation_source,
    appointment_id = COALESCE(EXCLUDED.appointment_id, patient_visit_authorizations.appointment_id),
    active = true
  RETURNING * INTO result;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.has_active_patient_visit_coverage(_patient_id UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.patient_visit_authorizations a
    WHERE a.patient_id = _patient_id
      AND a.authorization_date = CURRENT_DATE
      AND a.active
  );
$$;

-- Appointments activate an eligible patient's daily coverage at the first visit entry point.
CREATE OR REPLACE FUNCTION public.create_appointment_workflow(
  _patient_id UUID,
  _scheduled_at TIMESTAMPTZ,
  _department TEXT,
  _reason TEXT DEFAULT NULL
)
RETURNS public.appointments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  result public.appointments;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN RAISE EXCEPTION 'Patient does not exist'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'practitioner')
    OR public.has_role(auth.uid(), 'nurse') OR public.has_role(auth.uid(), 'midwife')
    OR public.has_role(auth.uid(), 'specialist_nurse') OR public.has_role(auth.uid(), 'front_desk')
  ) THEN RAISE EXCEPTION 'You are not authorized to create appointments'; END IF;
  IF _scheduled_at IS NULL THEN RAISE EXCEPTION 'Appointment time is required'; END IF;

  INSERT INTO public.appointments(patient_id, scheduled_at, department, reason, status, treatment_status)
  VALUES (_patient_id, _scheduled_at, NULLIF(trim(_department), ''), NULLIF(trim(_reason), ''), 'scheduled', 'scheduled')
  RETURNING * INTO result;

  IF EXISTS (SELECT 1 FROM public.patient_coverage_details(_patient_id)) THEN
    PERFORM public.activate_patient_visit_coverage(_patient_id, 'appointment', result.id, (_scheduled_at AT TIME ZONE 'UTC')::date);
  END IF;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_appointment(_appointment_id UUID)
RETURNS public.appointments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  result public.appointments;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'practitioner') OR public.has_role(auth.uid(), 'nurse') OR public.has_role(auth.uid(), 'midwife') OR public.has_role(auth.uid(), 'specialist_nurse')) THEN
    RAISE EXCEPTION 'Only attending clinical officers may claim appointments';
  END IF;
  UPDATE public.appointments
  SET attending_officer_id = auth.uid(), claimed_at = COALESCE(claimed_at, now()),
      treatment_status = CASE WHEN treatment_status = 'scheduled' THEN 'claimed' ELSE treatment_status END,
      updated_at = now()
  WHERE id = _appointment_id AND (attending_officer_id IS NULL OR attending_officer_id = auth.uid())
    AND COALESCE(treatment_status, 'scheduled') NOT IN ('completed', 'cancelled', 'no_show')
  RETURNING * INTO result;
  IF result.id IS NULL THEN RAISE EXCEPTION 'Appointment is already assigned, closed, or does not exist'; END IF;
  IF EXISTS (SELECT 1 FROM public.patient_coverage_details(result.patient_id)) THEN
    PERFORM public.activate_patient_visit_coverage(result.patient_id, 'appointment', result.id, CURRENT_DATE);
  END IF;
  RETURN result;
END;
$$;

-- Existing service-order callers continue to use their normal insert path. Eligible visits
-- are released inside the insert guard, so every department gets the same server decision.
CREATE OR REPLACE FUNCTION public.validate_service_order_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.amount, 0) > 0 AND public.has_active_patient_visit_coverage(NEW.patient_id) THEN
    NEW.status := 'released';
    NEW.payment_required := false;
    NEW.released_at := now();
    NEW.released_by := auth.uid();
    NEW.release_reason := 'Daily insured or partner coverage activated';
  ELSE
    NEW.status := 'pending_payment_approval';
    NEW.payment_required := COALESCE(NEW.amount, 0) > 0;
    NEW.released_at := NULL;
    NEW.released_by := NULL;
    NEW.release_reason := NULL;
  END IF;
  NEW.started_at := NULL;
  NEW.cancelled_at := NULL;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.service_order_event_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.service_order_events(service_order_id, from_status, to_status, actor_id, reason)
    VALUES (NEW.id, NULL, NEW.status, COALESCE(NEW.created_by, NEW.requested_by, auth.uid()), 'order_created');
    IF NEW.status = 'released' THEN
      INSERT INTO public.department_queues(service_order_id, department)
      VALUES (NEW.id, NEW.department)
      ON CONFLICT (service_order_id) DO NOTHING;
    END IF;
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.service_order_events(service_order_id, from_status, to_status, actor_id, reason)
    VALUES (NEW.id, OLD.status, NEW.status, COALESCE(NEW.released_by, NEW.approved_by, auth.uid()), NEW.release_reason);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS service_order_event_audit ON public.service_orders;
CREATE TRIGGER service_order_event_audit
AFTER INSERT OR UPDATE OF status ON public.service_orders
FOR EACH ROW EXECUTE FUNCTION public.service_order_event_trigger();

GRANT EXECUTE ON FUNCTION public.patient_coverage_details(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_patient_visit_coverage(UUID,TEXT,UUID,DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_active_patient_visit_coverage(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT) TO authenticated;
NOTIFY pgrst, 'reload schema';
