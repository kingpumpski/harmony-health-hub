-- Remove stale overloads that could shadow the reconciled workflow RPC contracts.
DROP FUNCTION IF EXISTS public.create_theatre_case(uuid,text,timestamptz,text,text,uuid);
DROP FUNCTION IF EXISTS public.create_transfusion_record(uuid,text,text,text,boolean);
NOTIFY pgrst,'reload schema';
