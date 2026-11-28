-- Keep nursing lifecycle writes behind the facility-aware SECURITY DEFINER RPCs.
-- Direct authenticated table mutations are not used by the application callers.

BEGIN;

REVOKE ALL ON TABLE public.nursing_shift_handovers FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.nursing_shift_handovers FROM authenticated;

REVOKE ALL ON TABLE public.nursing_care_plans FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.nursing_care_plans FROM authenticated;

-- Preserve the authenticated read surface; row visibility remains RLS-governed.
GRANT SELECT ON TABLE public.nursing_shift_handovers TO authenticated;
GRANT SELECT ON TABLE public.nursing_care_plans TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
