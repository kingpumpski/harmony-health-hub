
-- Add search_path to functions that were missing it
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, first_name, last_name)
  VALUES (
    NEW.id, NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'first_name',''),
    COALESCE(NEW.raw_user_meta_data->>'last_name','')
  );
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'patient');
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_invoice_totals()
RETURNS TRIGGER LANGUAGE PLPGSQL SET search_path = public
AS $$
DECLARE
  inv_id UUID; total_paid NUMERIC(10,2); inv_total NUMERIC(10,2);
BEGIN
  inv_id := COALESCE(NEW.invoice_id, OLD.invoice_id);
  IF inv_id IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(SUM(amount),0) INTO total_paid FROM public.payments WHERE invoice_id = inv_id;
  SELECT total_amount INTO inv_total FROM public.invoices WHERE id = inv_id;
  UPDATE public.invoices
  SET paid_amount = total_paid,
      status = CASE WHEN total_paid <= 0 THEN 'pending' WHEN total_paid < inv_total THEN 'partially_paid' ELSE 'paid' END,
      updated_at = now()
  WHERE id = inv_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER LANGUAGE PLPGSQL SET search_path = public
AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

-- Lock down SECURITY DEFINER helpers
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_clinical_staff(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_clinical_staff(uuid) TO authenticated;
