-- Financial settlement visibility bridge.
-- Reuses existing billing and insurance workflows; no direct payment mutation is introduced.

CREATE OR REPLACE FUNCTION public.notify_financial_settlement_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_patient_name TEXT;
  v_title TEXT;
  v_message TEXT;
  v_severity TEXT := 'info';
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  SELECT trim(concat_ws(' ', first_name, last_name))
    INTO v_patient_name
  FROM public.patients
  WHERE id = NEW.patient_id;

  IF NEW.status = 'paid' THEN
    v_title := 'Insurance payment recorded';
    v_message := 'Insurance claim ' || COALESCE(NEW.claim_number, NEW.id::text) || ' for ' || COALESCE(v_patient_name, 'patient') || ' is marked paid for GHS ' || to_char(COALESCE(NEW.amount_paid, 0), 'FM999999990.00') || '.';
    v_severity := 'success';
  ELSIF NEW.status IN ('partially_approved', 'resubmission_required', 'rejected') THEN
    v_title := 'Insurance settlement requires attention';
    v_message := 'Insurance claim ' || COALESCE(NEW.claim_number, NEW.id::text) || ' for ' || COALESCE(v_patient_name, 'patient') || ' is now ' || replace(NEW.status, '_', ' ') || '.';
    v_severity := 'warning';
  ELSE
    RETURN NEW;
  END IF;

  INSERT INTO public.notifications (
    recipient_role, title, message, severity, category, link,
    related_patient_id, related_entity_id, metadata
  ) VALUES (
    'accountant', v_title, v_message, v_severity, 'payment', '/billing',
    NEW.patient_id, NEW.id,
    jsonb_build_object(
      'workflow', 'financial_settlement',
      'claim_id', NEW.id,
      'invoice_id', NEW.invoice_id,
      'status', NEW.status,
      'amount_claimed', NEW.amount_claimed,
      'amount_approved', NEW.amount_approved,
      'amount_paid', NEW.amount_paid
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_financial_settlement_notification ON public.insurance_claims;
CREATE TRIGGER trg_financial_settlement_notification
AFTER UPDATE OF status ON public.insurance_claims
FOR EACH ROW
EXECUTE FUNCTION public.notify_financial_settlement_event();

REVOKE ALL ON FUNCTION public.notify_financial_settlement_event() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_financial_settlement_event() TO authenticated;
