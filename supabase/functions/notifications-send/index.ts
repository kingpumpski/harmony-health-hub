import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

Deno.serve(async req => {
  const pre=handlePreflight(req); if(pre)return pre;
  const cors=buildCorsHeaders(req), auth=req.headers.get('Authorization')??'';
  const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:auth}}});
  const {data:{user}}=await db.auth.getUser();
  if(!user)return new Response(JSON.stringify({error:'UNAUTHENTICATED'}),{status:401,headers:{...cors,'content-type':'application/json'}});
  const body=await req.json();
  const recipient=body.user_id??user.id;
  if(recipient!==user.id){
    const {data:allowed}=await db.rpc('notification_feature_enabled',{_key:'notifications.admin_send',_user_id:user.id});
    if(!allowed)return new Response(JSON.stringify({error:'FORBIDDEN'}),{status:403,headers:{...cors,'content-type':'application/json'}});
  }
  const {data,error}=await db.rpc('enqueue_notification_v2',{
    _event_name:body.event_name,_user_id:recipient,_payload:body.payload??{},_template_key:body.template_key,
    _channels:body.channels??['in_app'],_priority:body.priority??'medium',
    _scheduled_for:body.scheduled_for??new Date().toISOString(),
    _idempotency_key:body.idempotency_key??body.event_id??crypto.randomUUID(),
    _tenant_id:body.tenant_id??null,_locale:body.locale??null,_timezone:body.timezone??null,_facility_id:body.facility_id??null
  });
  if(error)return new Response(JSON.stringify({error:error.message}),{status:error.message.includes('disabled')?422:400,headers:{...cors,'content-type':'application/json'}});
  return new Response(JSON.stringify({queue_id:data,status:'queued'}),{status:202,headers:{...cors,'content-type':'application/json'}});
});