BEGIN;
DROP POLICY IF EXISTS medication_catalogue_authenticated_read ON public.medication_catalogue;
CREATE POLICY medication_catalogue_authenticated_read
ON public.medication_catalogue
FOR SELECT
TO authenticated
USING ((select auth.uid()) IS NOT NULL AND active);
COMMIT;