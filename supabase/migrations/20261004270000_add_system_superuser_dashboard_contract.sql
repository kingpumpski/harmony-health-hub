-- Add first-class System Superuser dashboard support without changing facility staff dashboard semantics.
DO $outer$
DECLARE
  v_sql text;
  v_roles_old text := '''admin'',''practitioner'',''nurse'',''midwife'',''specialist_nurse'',''lab_technician'',''radiologist'',''radiology_technician'',''pharmacist'',''accountant'',''front_desk'',''canteen'',''patient'',''it_admin''';
  v_roles_new text := '''admin'',''practitioner'',''nurse'',''midwife'',''specialist_nurse'',''lab_technician'',''radiologist'',''radiology_technician'',''pharmacist'',''accountant'',''front_desk'',''canteen'',''patient'',''it_admin'',''system_superuser''';
  v_branch text := E'  ELSIF v_role = ''system_superuser'' THEN\n    SELECT jsonb_agg(x ORDER BY x->>''key'') INTO v_cards FROM (\n      SELECT jsonb_build_object(''key'',''facilities'',''label'',''Registered facilities'',''value'',count(*),''href'',''/admin/facility-onboarding'',''description'',''Facilities registered on the Harmony platform'') x FROM public.platform_list_facilities()\n      UNION ALL SELECT jsonb_build_object(''key'',''staff'',''label'',''Platform users'',''value'',count(*),''href'',''/admin/users'',''description'',''User accounts available for platform administration'') FROM public.profiles\n      UNION ALL SELECT jsonb_build_object(''key'',''facility_sharing'',''label'',''Facility sharing'',''value'',count(*),''href'',''/admin/facility-sharing'',''description'',''Configured facility data-sharing agreements'') FROM public.facility_data_sharing_agreements\n    ) q;\n  ELSE\n    RAISE EXCEPTION ''Unsupported dashboard role'';';
BEGIN
  SELECT pg_get_functiondef('public.get_role_dashboard_summary()'::regprocedure) INTO v_sql;
  v_sql := replace(v_sql, 'IN (' || v_roles_old || ')', 'IN (' || v_roles_new || ')');
  v_sql := replace(v_sql, E'  ELSE\n    RAISE EXCEPTION ''Unsupported dashboard role'';', v_branch);
  EXECUTE v_sql;

  SELECT pg_get_functiondef('public.get_role_dashboard_summary_for_role(text)'::regprocedure) INTO v_sql;
  v_sql := replace(v_sql, 'IN (' || v_roles_old || ')', 'IN (' || v_roles_new || ')');
  v_sql := replace(v_sql, E'  ELSE\n    RAISE EXCEPTION ''Unsupported dashboard role'';', v_branch);
  EXECUTE v_sql;
END $outer$;

REVOKE ALL ON FUNCTION public.get_role_dashboard_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary() TO authenticated;
REVOKE ALL ON FUNCTION public.get_role_dashboard_summary_for_role(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary_for_role(text) TO authenticated;
NOTIFY pgrst, 'reload schema';
