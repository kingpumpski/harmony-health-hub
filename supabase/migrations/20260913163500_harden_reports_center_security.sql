-- Harden the Reports Center facility authorization helper.
-- The caller identity must always match auth.uid(); callers cannot supply
-- another user's UUID to test or inherit their facility access.

CREATE OR REPLACE FUNCTION public.has_facility_access(_user_id UUID, _facility_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND _user_id = auth.uid()
    AND (
      EXISTS (
        SELECT 1
        FROM public.facility_memberships fm
        WHERE fm.user_id = auth.uid()
          AND fm.facility_id = _facility_id
          AND fm.is_active = TRUE
      )
      OR public.has_role(auth.uid(), 'admin')
    )
$$;

REVOKE EXECUTE ON FUNCTION public.has_facility_access(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_facility_access(UUID, UUID) TO authenticated;
