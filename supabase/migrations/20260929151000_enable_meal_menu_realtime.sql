BEGIN;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='meal_menus') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.meal_menus;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='meal_menu_items') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.meal_menu_items;
    END IF;
  END IF;
END $$;

COMMIT;
