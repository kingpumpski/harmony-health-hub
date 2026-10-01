-- Pharmacy module access belongs to pharmacy/admin roles, not the practitioner role.
DELETE FROM public.role_permissions
WHERE role = 'practitioner'::public.app_role
  AND permission_key = 'pharmacy';
