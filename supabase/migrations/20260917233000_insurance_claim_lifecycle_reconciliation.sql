-- Insurance claims lifecycle hardening.
-- Keeps the existing canonical transition RPC while accepting the legacy
-- frontend parameter name `_to_status` through a compatibility wrapper.
-- Also emits accountant workflow notifications for material claim states.

CREATE OR REPLACE FUNCTION public.notify_insurance_claim_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_title TEXT;
  v_message TEXT;
  v_severity TEXT := 'info';
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'submitted' THEN
    v_title := 'Insurance claim submitted';
    v_message := 'Claim ' || COALESCE(NEW.claim_number, NEW.id::text) || ' has been submitted to ' || NEW.payer_name || '.';
  ELSIF NEW.status IN ('approved','partially_approved') THEN
    v_title := 'Insurance claim adjudicated';
    v_message := 'Claim ' || COALESCE(NEW.claim_number, NEW.id::text) || ' was ' || replace(NEW.status, '_', ' ') || '.';
    v_severity := 'warning';
  ELSIF NEW.status = 'rejected' THEN
    v_title := 'Insurance claim rejected';
    v_message := 'Claim ' || COALESCE(NEW.claim_number, NEW.id::text) || ' was rejected.';
    v_severity := 'warning';
  ELSIF NEW.status = 'resubmission_required' THEN
    v_title := 'Insurance claim requires resubmission';
    v_message := 'Claim ' || COALESCE(NEW.claim_number, NEW.id::text) || ' requires correction and resubmission.';
    v_severity := 'warning';
  ELSIF NEW.status = 'paid' THEN
    v_title := 'Insurance claim payment received';
    v_message := 'Claim ' || COALESCE(NEW.claim_number, NEW.id::text) || ' has been marked paid for GHS ' || to_char(COALESCE(NEW.amount_paid,0), 'FM999999990.00') || '.';
    v_severity := 'success';
  ELSE
    RETURN NEW;
  END IF;

  INSERT INTO public.notifications(
    recipient_role,
    title,
    message,
    severity,
    category,
    link,
    related_patient_id,
    related_entity_id,
    metadata
  ) VALUES (
    'accountant',
    v_title,
    v_message,
    v_severity,
    'insurance',
    '/insurance-claims',
    NEW.patient_id,
    NEW.id,
    jsonb_build_object('claim_id', NEW.id, 'from_status', OLD.status, 'to_status', NEW.status, 'invoice_id', NEW.invoice_id)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_insurance_claim_lifecycle_notification ON public.insurance_claims;
CREATE TRIGGER trg_insurance_claim_lifecycle_notification
AFTER UPDATE OF status ON public.insurance_claims
FOR EACH ROW
EXECUTE FUNCTION public.notify_insurance_claim_lifecycle();

-- Preserve the canonical six-argument implementation and expose a compatibility
-- contract that accepts either `_status` or the older `_to_status` key.
ALTER FUNCTION public.transition_insurance_claim(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT)
  RENAME TO transition_insurance_claim_canonical;

CREATE OR REPLACE FUNCTION public.transition_insurance_claim(
  _claim_id UUID,
  _status TEXT DEFAULT NULL,
  _amount_approved NUMERIC DEFAULT NULL,
  _amount_paid NUMERIC DEFAULT NULL,
  _rejection_reason TEXT DEFAULT NULL,
  _notes TEXT DEFAULT NULL,
  _to_status TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT := COALESCE(NULLIF(_status,''), NULLIF(_to_status,''));
BEGIN
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Claim status is required';
  END IF;

  RETURN public.transition_insurance_claim_canonical(
    _claim_id,
    v_status,
    _amount_approved,
    _amount_paid,
    _rejection_reason,
    _notes
  );
END;
$$;

REVOKE ALL ON FUNCTION public.transition_insurance_claim(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_insurance_claim(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT,TEXT) TO authenticated;
