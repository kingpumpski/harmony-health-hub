BEGIN;

INSERT INTO public.role_permissions(role,permission_key)
VALUES ('patient'::public.app_role,'meal_orders')
ON CONFLICT DO NOTHING;

COMMIT;
