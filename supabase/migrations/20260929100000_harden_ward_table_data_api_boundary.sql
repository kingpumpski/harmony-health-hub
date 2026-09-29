-- Harden the ward-management tables as data-API resources.
-- Ward/bed mutations are owned by server-side workflow RPCs; direct client
-- DML is not part of the canonical control plane. Anonymous clients should
-- not receive table-level privileges, even when RLS would block rows.

BEGIN;

REVOKE ALL ON TABLE public.ward_units FROM anon;
REVOKE ALL ON TABLE public.ward_units FROM PUBLIC;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.ward_units FROM authenticated;

REVOKE ALL ON TABLE public.ward_beds FROM anon;
REVOKE ALL ON TABLE public.ward_beds FROM PUBLIC;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.ward_beds FROM authenticated;

REVOKE ALL ON TABLE public.wards FROM anon;
REVOKE ALL ON TABLE public.wards FROM PUBLIC;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.wards FROM authenticated;

COMMIT;