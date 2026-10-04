ALTER FUNCTION public.record_notification_consent(text,text,boolean,text,text,inet) SET search_path='';
REVOKE ALL ON FUNCTION public.record_notification_consent(text,text,boolean,text,text,inet) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_notification_consent(text,text,boolean,text,text,inet) TO authenticated;
ALTER FUNCTION public.register_notification_device(text,text,text,text) SET search_path='';
REVOKE ALL ON FUNCTION public.register_notification_device(text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.register_notification_device(text,text,text,text) TO authenticated;
ALTER FUNCTION public.revoke_notification_device(text) SET search_path='';
REVOKE ALL ON FUNCTION public.revoke_notification_device(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.revoke_notification_device(text) TO authenticated;