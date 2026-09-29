BEGIN;

CREATE TABLE IF NOT EXISTS public.meal_menus (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_date DATE NOT NULL,
  meal_period TEXT NOT NULL CHECK (meal_period IN ('breakfast','morning_snack','lunch','afternoon_snack','dinner','night_snack')),
  available_from TIMESTAMPTZ,
  available_until TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','archived')),
  notes TEXT,
  created_by UUID NOT NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(service_date, meal_period)
);

CREATE TABLE IF NOT EXISTS public.meal_menu_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_id UUID NOT NULL REFERENCES public.meal_menus(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  dietary_tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  allergens TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ingredients TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_meal_menus_service_date_period ON public.meal_menus(service_date, meal_period);
CREATE INDEX IF NOT EXISTS idx_meal_menus_published_window ON public.meal_menus(status, service_date, available_from, available_until);
CREATE INDEX IF NOT EXISTS idx_meal_menu_items_menu_order ON public.meal_menu_items(menu_id, sort_order);

ALTER TABLE public.meal_menus ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meal_menu_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS meal_menus_authenticated_read ON public.meal_menus;
CREATE POLICY meal_menus_authenticated_read ON public.meal_menus
  FOR SELECT TO authenticated
  USING (status = 'published' OR public.has_role((SELECT auth.uid()), 'admin') OR public.has_role((SELECT auth.uid()), 'canteen'));

DROP POLICY IF EXISTS meal_menu_items_authenticated_read ON public.meal_menu_items;
CREATE POLICY meal_menu_items_authenticated_read ON public.meal_menu_items
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.meal_menus m WHERE m.id = menu_id AND (m.status = 'published' OR public.has_role((SELECT auth.uid()), 'admin') OR public.has_role((SELECT auth.uid()), 'canteen'))));

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.meal_menus FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.meal_menu_items FROM authenticated, anon;
REVOKE ALL ON public.meal_menus FROM anon;
REVOKE ALL ON public.meal_menu_items FROM anon;
GRANT SELECT ON public.meal_menus TO authenticated;
GRANT SELECT ON public.meal_menu_items TO authenticated;

CREATE OR REPLACE FUNCTION public.save_canteen_menu(
  _service_date DATE,
  _meal_period TEXT,
  _available_from TIMESTAMPTZ DEFAULT NULL,
  _available_until TIMESTAMPTZ DEFAULT NULL,
  _items JSONB DEFAULT '[]'::JSONB,
  _notes TEXT DEFAULT NULL,
  _publish BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_menu public.meal_menus;
  v_item JSONB;
  v_order INTEGER := 0;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'canteen')) THEN RAISE EXCEPTION 'Canteen or administrator role required'; END IF;
  IF _service_date IS NULL OR _meal_period NOT IN ('breakfast','morning_snack','lunch','afternoon_snack','dinner','night_snack') THEN RAISE EXCEPTION 'Valid service date and meal period are required'; END IF;
  IF _available_from IS NOT NULL AND _available_until IS NOT NULL AND _available_until <= _available_from THEN RAISE EXCEPTION 'Menu availability end must be after start'; END IF;
  IF _items IS NULL OR jsonb_typeof(_items) <> 'array' THEN RAISE EXCEPTION 'Menu items must be an array'; END IF;

  INSERT INTO public.meal_menus(service_date,meal_period,available_from,available_until,status,notes,created_by,updated_at)
  VALUES(_service_date,_meal_period,_available_from,_available_until,CASE WHEN _publish THEN 'published' ELSE 'draft' END,NULLIF(pg_catalog.btrim(_notes),''),uid,pg_catalog.now())
  ON CONFLICT(service_date,meal_period) DO UPDATE SET
    available_from=EXCLUDED.available_from,
    available_until=EXCLUDED.available_until,
    status=CASE WHEN _publish THEN 'published' ELSE CASE WHEN public.meal_menus.status='published' THEN 'published' ELSE 'draft' END END,
    notes=EXCLUDED.notes,
    updated_at=pg_catalog.now()
  RETURNING * INTO v_menu;

  DELETE FROM public.meal_menu_items WHERE menu_id=v_menu.id;
  FOR v_item IN SELECT value FROM jsonb_array_elements(_items) LOOP
    IF NULLIF(pg_catalog.btrim(v_item->>'name'),'') IS NULL THEN RAISE EXCEPTION 'Every menu item requires a name'; END IF;
    INSERT INTO public.meal_menu_items(menu_id,name,description,dietary_tags,allergens,ingredients,sort_order,active)
    VALUES(v_menu.id,pg_catalog.btrim(v_item->>'name'),NULLIF(pg_catalog.btrim(v_item->>'description'),''),
      COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_item->'dietary_tags','[]'::jsonb))),ARRAY[]::TEXT[]),
      COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_item->'allergens','[]'::jsonb))),ARRAY[]::TEXT[]),
      NULLIF(pg_catalog.btrim(v_item->>'ingredients'),''),COALESCE((v_item->>'sort_order')::INTEGER,v_order),COALESCE((v_item->>'active')::BOOLEAN,true));
    v_order := v_order + 1;
  END LOOP;

  RETURN jsonb_build_object('menu_id',v_menu.id,'service_date',v_menu.service_date,'meal_period',v_menu.meal_period,'status',v_menu.status,'item_count',(SELECT count(*) FROM public.meal_menu_items WHERE menu_id=v_menu.id));
END;
$$;

REVOKE ALL ON FUNCTION public.save_canteen_menu(DATE,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,JSONB,TEXT,BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_canteen_menu(DATE,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,JSONB,TEXT,BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_canteen_active_patient_orders()
RETURNS TABLE (
  order_id UUID, patient_id UUID, patient_code TEXT, patient_name TEXT, meal_type TEXT,
  scheduled_for TIMESTAMPTZ, order_status TEXT, plan_type TEXT, dietary_restrictions TEXT,
  underlying_conditions TEXT, current_diagnoses JSONB, meal_notes TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'canteen')) THEN RAISE EXCEPTION 'Canteen or administrator role required'; END IF;

  RETURN QUERY
  SELECT mo.id,p.id,p.patient_code,pg_catalog.concat_ws(' ',p.first_name,p.last_name),mo.meal_type,mo.scheduled_for,mo.status,
    mp.plan_type,mp.restrictions,NULLIF(pg_catalog.btrim(p.chronic_conditions),''),
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object('diagnosis',d.diagnosis,'icd_code',d.icd_code,'principal',COALESCE(d.is_principal,false),'provisional',COALESCE(d.is_provisional,false)) ORDER BY d.is_principal DESC,d.created_at DESC)
      FROM public.diagnoses d LEFT JOIN public.encounters e ON e.id=d.encounter_id
      WHERE d.patient_id=p.id AND (e.id IS NULL OR e.status NOT IN ('completed','cancelled'))
        AND NULLIF(pg_catalog.btrim(d.diagnosis),'') IS NOT NULL
    ),'[]'::jsonb),mo.notes
  FROM public.meal_orders mo
  JOIN public.patients p ON p.id=mo.patient_id
  LEFT JOIN public.meal_plans mp ON mp.id=mo.meal_plan_id
  WHERE mo.status <> 'delivered'
    AND mo.scheduled_for >= pg_catalog.now() - INTERVAL '2 hours'
    AND mo.scheduled_for < pg_catalog.now() + INTERVAL '36 hours'
  ORDER BY mo.scheduled_for ASC,p.last_name ASC,p.first_name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_canteen_active_patient_orders() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_canteen_active_patient_orders() TO authenticated;

CREATE OR REPLACE FUNCTION public.broadcast_canteen_context_refresh()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM realtime.send(
    jsonb_build_object('source_table',TG_TABLE_NAME,'operation',TG_OP,'refreshed_at',pg_catalog.now()),
    'canteen_context_changed','canteen:operations',true
  );
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS meal_orders_canteen_context_refresh ON public.meal_orders;
CREATE TRIGGER meal_orders_canteen_context_refresh AFTER INSERT OR UPDATE OR DELETE ON public.meal_orders FOR EACH ROW EXECUTE FUNCTION public.broadcast_canteen_context_refresh();
DROP TRIGGER IF EXISTS meal_plans_canteen_context_refresh ON public.meal_plans;
CREATE TRIGGER meal_plans_canteen_context_refresh AFTER INSERT OR UPDATE OR DELETE ON public.meal_plans FOR EACH ROW EXECUTE FUNCTION public.broadcast_canteen_context_refresh();
DROP TRIGGER IF EXISTS patients_canteen_context_refresh ON public.patients;
CREATE TRIGGER patients_canteen_context_refresh AFTER INSERT OR UPDATE OR DELETE ON public.patients FOR EACH ROW EXECUTE FUNCTION public.broadcast_canteen_context_refresh();
DROP TRIGGER IF EXISTS diagnoses_canteen_context_refresh ON public.diagnoses;
CREATE TRIGGER diagnoses_canteen_context_refresh AFTER INSERT OR UPDATE OR DELETE ON public.diagnoses FOR EACH ROW EXECUTE FUNCTION public.broadcast_canteen_context_refresh();
DROP TRIGGER IF EXISTS encounters_canteen_context_refresh ON public.encounters;
CREATE TRIGGER encounters_canteen_context_refresh AFTER INSERT OR UPDATE OR DELETE ON public.encounters FOR EACH ROW EXECUTE FUNCTION public.broadcast_canteen_context_refresh();

REVOKE ALL ON FUNCTION public.broadcast_canteen_context_refresh() FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS canteen_operations_broadcast_read ON realtime.messages;
CREATE POLICY canteen_operations_broadcast_read ON realtime.messages
  FOR SELECT TO authenticated
  USING (topic = 'realtime:canteen:operations' AND (public.has_role((SELECT auth.uid()),'admin') OR public.has_role((SELECT auth.uid()),'canteen')));

COMMIT;