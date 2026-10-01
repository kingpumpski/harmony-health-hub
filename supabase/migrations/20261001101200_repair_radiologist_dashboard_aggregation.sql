-- Prevent the radiologist role dashboard from failing when its first UNION branch
-- is aggregated by the outer jsonb_agg(x ...) expression.
--
-- This repair intentionally patches both canonical dashboard functions:
--   1) get_role_dashboard_summary() — canonical source used by later wrapper migrations
--   2) get_role_dashboard_summary_for_role(text) — authenticated active-role API
--
-- The replacement is deterministic and fails closed if the expected defect is not
-- present, preventing a silent no-op migration on a structurally different function.

DO $repair$
DECLARE
  v_signature regprocedure;
  v_definition text;
  v_old text := $needle$
SELECT jsonb_build_object('key','ready','label','Ready for interpretation','value',count(*),'href','/radiology','description','Released or queued studies awaiting radiologist interpretation') FROM public.imaging_orders WHERE status IN ('released','queued')
      UNION ALL SELECT jsonb_build_object('key','urgent','label','Urgent / STAT','value',count(*),'href','/radiology','description','Urgent studies awaiting radiologist attention') FROM public.imaging_orders WHERE priority IN ('urgent','stat') AND status IN ('released','queued','in_progress')
$needle$;
  v_new text := $replacement$
SELECT jsonb_build_object('key','ready','label','Ready for interpretation','value',count(*),'href','/radiology','description','Released or queued studies awaiting radiologist interpretation') x FROM public.imaging_orders WHERE status IN ('released','queued')
      UNION ALL SELECT jsonb_build_object('key','urgent','label','Urgent / STAT','value',count(*),'href','/radiology','description','Urgent studies awaiting radiologist attention') FROM public.imaging_orders WHERE priority IN ('urgent','stat') AND status IN ('released','queued','in_progress')
$replacement$;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.get_role_dashboard_summary()'::regprocedure,
    'public.get_role_dashboard_summary_for_role(text)'::regprocedure
  ]
  LOOP
    SELECT pg_get_functiondef(v_signature) INTO v_definition;

    IF position(v_old IN v_definition) = 0 THEN
      IF position('Ready for interpretation' IN v_definition) = 0 THEN
        RAISE EXCEPTION 'Expected radiologist dashboard branch is missing from %', v_signature;
      END IF;

      -- A correctly repaired function is acceptable and makes the migration
      -- idempotent across reconciled environments.
      IF position(v_new IN v_definition) > 0 THEN
        CONTINUE;
      END IF;

      RAISE EXCEPTION 'Radiologist dashboard branch in % has unexpected SQL shape; refusing silent patch', v_signature;
    END IF;

    v_definition := replace(v_definition, v_old, v_new);
    EXECUTE v_definition;
  END LOOP;
END $repair$;

REVOKE ALL ON FUNCTION public.get_role_dashboard_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary() TO authenticated;
REVOKE ALL ON FUNCTION public.get_role_dashboard_summary_for_role(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary_for_role(text) TO authenticated;

NOTIFY pgrst, 'reload schema';
