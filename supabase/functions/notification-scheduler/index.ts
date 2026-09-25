import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

Deno.serve(async req=>{
 const pre=handlePreflight(req);if(pre)return pre;const cors=buildCorsHeaders(req),auth=req.headers.get('Authorization')??'',key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!key||auth!==`Bearer ${key}`)return new Response(JSON.stringify({error:'Worker authentication required'}),{status:401,headers:{...cors,'content-type':'application/json'}});
 const db=createClient(Deno.env.get('SUPABASE_URL')!,key);
 const {data:due,error}=await db.from('scheduled_notifications').select('*').eq('status','scheduled').lte('run_at',new Date().toISOString()).order('run_at').limit(100);
 if(error)return new Response(JSON.stringify({error:error.message}),{status:500,headers:{...cors,'content-type':'application/json'}});
 let queued=0;
 for(const row of due??[]){const {error:e}=await db.rpc('enqueue_notification_v2',{_event_name:row.event_name,_user_id:row.user_id,_payload:row.payload,_template_key:row.template_key,_channels:row.channels,_priority:row.priority,_scheduled_for:new Date().toISOString(),_idempotency_key:row.idempotency_key,_tenant_id:row.tenant_id,_locale:row.locale,_timezone:row.timezone});if(!e){await db.from('scheduled_notifications').update({status:'queued',updated_at:new Date().toISOString()}).eq('id',row.id).eq('status','scheduled');queued++;}}
 return new Response(JSON.stringify({checked:due?.length??0,queued}),{headers:{...cors,'content-type':'application/json'}});
});