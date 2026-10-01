BEGIN;

-- Practitioners can administer medication in the clinical workflow, but must not
-- receive the pharmacy department's dispensing/inventory workspace capability.
DELETE FROM public.role_permissions
WHERE role = 'practitioner'
  AND permission_key = 'pharmacy';

COMMIT;
