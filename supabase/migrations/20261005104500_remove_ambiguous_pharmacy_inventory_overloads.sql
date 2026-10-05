DROP FUNCTION IF EXISTS public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric);
DROP FUNCTION IF EXISTS public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric);
NOTIFY pgrst, 'reload schema';