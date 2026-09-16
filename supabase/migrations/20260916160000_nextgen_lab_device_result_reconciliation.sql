-- Next-gen laboratory/device convergence: device transport may enter the durable
-- interoperability ledger, but only authorized laboratory staff can reconcile a
-- device result into the canonical laboratory workflow.

CREATE TABLE IF NOT EXISTS public.lab_result_qc_checks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_order_id UUID NOT NULL REFERENCES public.lab_orders(id) ON DELETE CASCADE,
  integration_message_id UUID REFERENCES public.platform_integration_messages(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','passed','failed')),
  qc_method TEXT NOT NULL,
  qc_reference TEXT,
  checked_by UUID REFERENCES auth.users(id),
  checked_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_lab_qc_message_order
  ON public.lab_result_qc_checks(integration_message_id, lab_order_id)
  WHERE integration_message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_lab_qc_order_status
  ON public.lab_result_qc_checks(lab_order_id, status, created_at DESC);

ALTER TABLE public.lab_result_qc_checks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "clinical staff read lab qc" ON public.lab_result_qc_checks;
CREATE POLICY "clinical staff read lab qc" ON public.lab_result_qc_checks
  FOR SELECT TO authenticated
  USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS "admins manage lab qc" ON public.lab_result_qc_checks;
CREATE POLICY "admins manage lab qc" ON public.lab_result_qc_checks
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin'))
  WITH CHECK (public.has_role(auth.uid(),'admin'));

DROP TRIGGER IF EXISTS t_lab_qc_updated ON public.lab_result_qc_checks;
CREATE TRIGGER t_lab_qc_updated
BEFORE UPDATE ON public.lab_result_qc_checks
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE OR REPLACE FUNCTION public.record_lab_device_qc(
  _integration_message_id UUID,
  _lab_order_id UUID,
  _status TEXT,
  _qc_method TEXT,
  _qc_reference TEXT DEFAULT NULL,
  _notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT (public.has_role(auth.uid(),'lab_technician') OR public.has_role(auth.uid(),'admin')) THEN
    RAISE EXCEPTION 'Laboratory authorization required';
  END IF;
  IF _status NOT IN ('passed','failed') THEN
    RAISE EXCEPTION 'QC status must be passed or failed';
  END IF;
  IF _qc_method IS NULL OR btrim(_qc_method) = '' THEN
    RAISE EXCEPTION 'QC method is required';
  END IF;

  PERFORM 1 FROM public.lab_orders WHERE id = _lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;

  IF _integration_message_id IS NOT NULL THEN
    PERFORM 1 FROM public.platform_integration_messages
    WHERE id = _integration_message_id
      AND direction = 'inbound'
      AND lifecycle_state IN ('queued','processing')
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Integration message is not eligible for laboratory QC'; END IF;
  END IF;

  INSERT INTO public.lab_result_qc_checks(
    lab_order_id, integration_message_id, status, qc_method, qc_reference,
    checked_by, checked_at, notes
  ) VALUES (
    _lab_order_id, _integration_message_id, _status, btrim(_qc_method),
    NULLIF(btrim(_qc_reference), ''), auth.uid(), now(), _notes
  )
  ON CONFLICT (integration_message_id, lab_order_id)
  WHERE integration_message_id IS NOT NULL
  DO UPDATE SET
    status = EXCLUDED.status,
    qc_method = EXCLUDED.qc_method,
    qc_reference = EXCLUDED.qc_reference,
    checked_by = EXCLUDED.checked_by,
    checked_at = EXCLUDED.checked_at,
    notes = EXCLUDED.notes,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reconcile_device_lab_result(
  _integration_message_id UUID,
  _lab_order_id UUID,
  _result_text TEXT,
  _numeric_value NUMERIC DEFAULT NULL,
  _interpretation TEXT DEFAULT NULL,
  _is_abnormal BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_message public.platform_integration_messages%ROWTYPE;
  v_order public.lab_orders%ROWTYPE;
  v_catalog public.lab_test_catalogue%ROWTYPE;
  v_qc public.lab_result_qc_checks%ROWTYPE;
  v_result UUID;
BEGIN
  IF NOT (public.has_role(auth.uid(),'lab_technician') OR public.has_role(auth.uid(),'admin')) THEN
    RAISE EXCEPTION 'Laboratory authorization required';
  END IF;
  IF _result_text IS NULL OR btrim(_result_text) = '' THEN
    RAISE EXCEPTION 'Result value is required';
  END IF;

  SELECT * INTO v_message
  FROM public.platform_integration_messages
  WHERE id = _integration_message_id
    AND direction = 'inbound'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Integration message not found'; END IF;
  IF v_message.standard NOT IN ('ASTM','HL7_V2') THEN
    RAISE EXCEPTION 'Only ASTM and HL7 laboratory messages may use this reconciliation path';
  END IF;
  IF v_message.lifecycle_state NOT IN ('queued','processing') THEN
    RAISE EXCEPTION 'Integration message is not awaiting laboratory reconciliation';
  END IF;

  SELECT * INTO v_order FROM public.lab_orders WHERE id = _lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  IF v_order.status NOT IN ('sample_collected','in_progress') THEN
    RAISE EXCEPTION 'Laboratory order is not eligible for result reconciliation';
  END IF;
  IF v_message.patient_reference IS NULL OR v_message.patient_reference <> v_order.patient_id::TEXT THEN
    RAISE EXCEPTION 'Device patient reference does not match laboratory order patient';
  END IF;

  SELECT * INTO v_qc
  FROM public.lab_result_qc_checks
  WHERE integration_message_id = _integration_message_id
    AND lab_order_id = _lab_order_id
  ORDER BY checked_at DESC NULLS LAST, created_at DESC
  LIMIT 1;
  IF NOT FOUND OR v_qc.status <> 'passed' THEN
    RAISE EXCEPTION 'Laboratory QC approval is required before result reconciliation';
  END IF;

  IF v_order.lab_test_catalogue_id IS NOT NULL THEN
    SELECT * INTO v_catalog FROM public.lab_test_catalogue WHERE id = v_order.lab_test_catalogue_id;
    IF v_catalog.id IS NULL OR NOT v_catalog.active THEN
      RAISE EXCEPTION 'Laboratory test catalogue entry is unavailable or inactive';
    END IF;
  END IF;

  INSERT INTO public.lab_results(
    lab_order_id, result_data, interpretation, is_abnormal, entered_by, status,
    numeric_value, unit, reference_low, reference_high, abnormal_flag, notes
  ) VALUES (
    _lab_order_id,
    jsonb_build_object('value', btrim(_result_text), 'source', 'device_reconciled', 'integration_message_id', _integration_message_id),
    _interpretation, _is_abnormal, auth.uid(), 'completed',
    _numeric_value, v_catalog.unit, v_catalog.reference_low, v_catalog.reference_high,
    CASE WHEN _is_abnormal THEN 'abnormal' ELSE 'normal' END,
    'Reconciled from validated device integration message after laboratory QC.'
  ) RETURNING id INTO v_result;

  UPDATE public.lab_orders
  SET status = 'completed', updated_at = now()
  WHERE id = _lab_order_id;

  UPDATE public.platform_integration_messages
  SET lifecycle_state = 'delivered', last_error = NULL, updated_at = now()
  WHERE id = _integration_message_id;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.record_lab_device_qc(UUID,UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reconcile_device_lab_result(UUID,UUID,TEXT,NUMERIC,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_lab_device_qc(UUID,UUID,TEXT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_device_lab_result(UUID,UUID,TEXT,NUMERIC,TEXT,BOOLEAN) TO authenticated;

-- Canonical clinical result mutation remains server-authoritative.
REVOKE INSERT, UPDATE, DELETE ON public.lab_results FROM authenticated;
REVOKE UPDATE ON public.lab_orders FROM authenticated;

COMMENT ON FUNCTION public.reconcile_device_lab_result(UUID,UUID,TEXT,NUMERIC,TEXT,BOOLEAN)
IS 'Authoritative laboratory device reconciliation: requires lab authorization, active ASTM/HL7 ledger message, patient/order match, sample lifecycle eligibility, and passed laboratory QC. Never accepts raw device transport as a finalized result by itself.';
