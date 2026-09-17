-- Consolidate insurance settlement notifications.
-- The prior financial-settlement bridge duplicated statuses already handled by
-- notify_insurance_claim_lifecycle(). Keep one canonical trigger per claim update.

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
  v_category TEXT := 'insurance';
  v_link TEXT := '/insurance-claims';
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
    v_title := 'Insurance payment received';
    v_message := 'Claim ' || COALESCE(NEW.claim_number, NEW.id::text) || ' has been marked paid for GHS ' || to_char(COALESCE(NEW.amount_paid,0), 'FM999999990.00') || '.';
    v_severity := 'success';
  ELSE
    RETURN NEW;
  END IF;

  -- Settlement states also enter the Accounts/payment work queue so the
  -- financial dashboard and notification stream share one canonical event.
  IF NEW.status IN ('partially_approved','rejected','resubmission_required','paid') THEN
    v_category := 'payment';
    v_link := '/billing';
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
    v_category,
    v_link,
    NEW.patient_id,
    NEW.id,
    jsonb_build_object(
      'workflow', CASE WHEN NEW.status IN ('partially_approved','rejected','resubmission_required','paid') THEN 'financial_settlement' ELSE 'insurance_claim_lifecycle' END,
      'claim_id', NEW.id,
      'from_status', OLD.status,
      'to_status', NEW.status,
      'invoice_id', NEW.invoice_id,
      'amount_claimed', NEW.amount_claimed,
      'amount_approved', NEW.amount_approved,
      'amount_paid', NEW.amount_paid
    )
  );

  RETURN NEW;
END;
$$;

-- Remove the redundant second trigger/function introduced by the earlier
-- settlement bridge. The canonical lifecycle trigger above now owns all
-- insurance status notifications.
DROP TRIGGER IF EXISTS trg_financial_settlement_notification ON public.insurance_claims;
DROP FUNCTION IF EXISTS public.notify_financial_settlement_event();

DROP TRIGGER IF EXISTS trg_insurance_claim_lifecycle_notification ON public.insurance_claims;
CREATE TRIGGER trg_insurance_claim_lifecycle_notification
AFTER UPDATE OF status ON public.insurance_claims
FOR EACH ROW
EXECUTE FUNCTION public.notify_insurance_claim_lifecycle();

REVOKE ALL ON FUNCTION public.notify_insurance_claim_lifecycle() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_insurance_claim_lifecycle() TO authenticated;
