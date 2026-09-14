-- Harden insurance-case mutation authority.
-- Case updates remain available through the authenticated server-authoritative RPC.

REVOKE INSERT, UPDATE, DELETE ON public.insurance_cases FROM authenticated;

REVOKE ALL ON FUNCTION public.update_insurance_case(
  uuid,
  text,
  text,
  text,
  numeric,
  numeric,
  text
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.update_insurance_case(
  uuid,
  text,
  text,
  text,
  numeric,
  numeric,
  text
) TO authenticated;
