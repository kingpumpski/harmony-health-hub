-- Remove policies from the earlier system-settings migration that were
-- applied before the canonical lab catalogue policy set was established.
DROP POLICY IF EXISTS "lab catalogue staff read" ON public.lab_test_catalogue;
DROP POLICY IF EXISTS "lab catalogue admin write" ON public.lab_test_catalogue;
