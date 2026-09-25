import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

type Channel = 'in_app'|'email'|'sms'|'push'|'whatsapp'|'voice';
const BATCH=50, BACKOFF=[10,30,120,600,3600];
const json=(body:unknown,status=200,cors:Record<string,string>={})=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});

async function external(channel:Channel, recipient:{email?:string;phone?:string}, subject:string, body:string) {
  if(channel==='email'){
    if(!recipient.email) return {ok:false,provider:'none',error:'Recipient email unavailable'};
    const url=Deno.env.get('NOTIFY_EMAIL_URL'), key=Deno.env.get('NOTIFY_EMAIL_API_KEY');
    if(!url||!key) return {ok:false,provider:'generic_http',error:'Email provider not configured'};
    const r=await fetch(url,{method:'POST',headers:{'content-type':'application/json',authorization:`Bearer ${key}`},body:JSON.stringify({to:recipient.email,subject,body})});
    return {ok:r.ok,provider:'generic_http',id:r.headers.get('x-message-id')??undefined,error:r.ok?undefined:(await r.text()).slice(0,500)};
  }
  if(channel==='push') return {ok:false,provider:'fcm',error:'Push requires a registered device token'};
  const account=Deno.env.get('TWILIO_ACCOUNT_SID'),token=Deno.env.get('TWILIO_AUTH_TOKEN');
  if(!account||!token||!recipient.phone) return {ok:false,provider:'twilio',error:'Twilio recipient/provider not configured'};
  if(channel==='sms'||channel==='whatsapp'){
    const from=channel==='whatsapp'?Deno.env.get('TWILIO_WHATSAPP_FROM'):Deno.env.get('TWILIO_SMS_FROM');
    if(!from) return {ok:false,provider:'twilio',error:'Twilio sender not configured'};
    const to=channel==='whatsapp'?`whatsapp:${recipient.phone}`:recipient.phone;
    const form=new URLSearchParams({To:to,From:from,Body:body}), auth=btoa(`${account}:${token}`);
    const r=await fetch(`https://api.twilio.com/2010-04-01/Accounts/${account}/Messages.json`,{method:'POST',headers:{authorization:`Basic ${auth}`,'content-type':'application/x-www-form-urlencoded'},body:form});
    const d=await r.json().catch(()=>({})); return {ok:r.ok,provider:'twilio',id:d.sid,error:r.ok?undefined:String(d.message??d.error_message??'Provider error')};
  }
  if(channel==='voice'){
    const from=Deno.env.get('TWILIO_VOICE_FROM'),url=Deno.env.get('TWILIO_VOICE_TWIML_URL');
    if(!from||!url) return {ok:false,provider:'twilio',error:'Voice sender or TwiML URL not configured'};
    const form=new URLSearchParams({To:recipient.phone!,From:from,Url:url}),auth=btoa(`${account}:${token}`);
    const r=await fetch(`https://api.twilio.com/2010-04-01/Accounts/${account}/Calls.json`,{method:'POST',headers:{authorization:`Basic ${auth}`,'content-type':'application/x-www-form-urlencoded'},body:form});
    const d=await r.json().catch(()=>({})); return {ok:r.ok,provider:'twilio',id:d.sid,error:r.ok?undefined:String(d.message??d.error_message??'Provider error')};
  }
  return {ok:false,provider:'none',error:'Unsupported channel'};
}
function quiet(now:Date,tz:string,start:string,end:string){const p=new Intl.DateTimeFormat('en-GB',{timeZone:tz,hour:'2-digit',minute:'2-digit',hour12:false}).formatToParts(now);const m=Number(p.find(x=>x.type==='hour')?.value??0)*60+Number(p.find(x=>x.type==='minute')?.value??0);const [sh,sm]=start.split(':').map(Number),[eh,em]=end.split(':').map(Number),s=sh*60+sm,e=eh*60+em;return s>e?m>=s||m<e:m>=s&&m<e;}

Deno.serve(async req=>{
 const pre=handlePreflight(req);if(pre)return pre;const cors=buildCorsHeaders(req),auth=req.headers.get('Authorization')??'',key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!key||auth!==`Bearer ${key}`)return json({error:'Worker authentication required'},401,cors);
 const db=createClient(Deno.env.get('SUPABASE_URL')!,key);const {data:rows,error}=await db.rpc('claim_notification_queue',{_limit:BATCH});
 if(error)return json({error:'Notification queue claim failed'},500,cors);
 let delivered=0,failed=0;
 for(const row of rows??[]){const attempt=(row.attempts??0)+1,p=(row.payload??{}) as Record<string,unknown>;try{
   const userId=row.user_id??p.user_id;const [{data:profile},{data:prefs},{data:event}]=await Promise.all([
    db.from('profiles').select('email,phone').eq('id',userId).maybeSingle(),
    db.from('user_notification_preferences').select('*').eq('user_id',userId).maybeSingle(),
    db.from('notification_events').select('*').eq('event_name',row.event_name).maybeSingle()
   ]);
   if(!profile)throw new Error('Recipient profile not found');
   const priority=String(row.priority??event?.priority_level??'medium');const pref=prefs??{timezone:'Africa/Accra',quiet_hours_start:'22:00:00',quiet_hours_end:'07:00:00',pause_non_critical:false,channel_preferences:{in_app:true}};
   if(quiet(new Date(),pref.timezone,pref.quiet_hours_start,pref.quiet_hours_end)&&event?.quiet_hours_behavior==='delay'&&priority!=='critical'){await db.from('notification_queue').update({status:'pending',next_attempt_at:new Date(Date.now()+1800000).toISOString(),updated_at:new Date().toISOString()}).eq('id',row.id).eq('status','processing');continue;}
   const channels=(Array.isArray(row.fallback_channels)?row.fallback_channels:['in_app']) as Channel[];let ok=false,last='No eligible channel';
   for(const channel of channels){ const {data:channelConfig}=await db.from('notification_channels').select('enabled').eq('code',channel).maybeSingle(); if(!channelConfig?.enabled){last='Channel disabled';continue;}
    if(channel!=='in_app'&&priority!=='critical'&&(pref.pause_non_critical||pref.channel_preferences?.[channel]!==true))continue;
    const started=Date.now();
    if(channel==='in_app'){
      const {data:n,error:e}=await db.from('notifications').insert({recipient_user_id:userId,title:String(p.title??'Notification'),message:String(p.message??'You have a new notification.'),severity:String(p.severity??'info'),category:String(p.category??'other'),link:p.link??null,related_patient_id:p.related_patient_id??null,related_entity_id:p.related_entity_id??null,metadata:{...(p.metadata as Record<string,unknown>??{}),event_name:row.event_name},source_queue_id:row.id}).select('id').single();
      if(e&&e.code!=='23505'){last=e.message;continue;} const nid=n?.id;
      await db.from('notification_delivery_logs').insert({notification_id:nid,queue_id:row.id,user_id:userId,channel,provider:'supabase_realtime',status:'delivered',attempt,latency_ms:Date.now()-started});
      await db.from('notification_audit').insert({notification_id:nid,queue_id:row.id,user_id:userId,event_name:row.event_name,action:'delivery',channel,outcome:'delivered',metadata:{attempt}});ok=true;break;
    }
    const r=await external(channel,{email:profile.email??undefined,phone:profile.phone??undefined},String(p.subject??p.title??'Health notification'),String(p.message??'Please sign in to your secure health record.'));
    await db.from('notification_delivery_logs').insert({queue_id:row.id,user_id:userId,channel,provider:r.provider,status:r.ok?'sent':'failed',provider_message_id:r.id??null,attempt,latency_ms:Date.now()-started,error_message:r.error??null});
    if(r.ok){ok=true;break;}last=r.error??last;
   }
   if(!ok)throw new Error(last);
   await db.from('notification_queue').update({status:'delivered',attempts:attempt,delivered_at:new Date().toISOString(),last_error:null,updated_at:new Date().toISOString()}).eq('id',row.id).eq('status','processing');delivered++;
 }catch(err){const msg=err instanceof Error?err.message:String(err),max=row.max_attempts??5,final=attempt>=max,b=BACKOFF[Math.min(attempt-1,BACKOFF.length-1)];await db.from('notification_queue').update({status:final?'failed':'pending',attempts:attempt,last_error:msg.slice(0,500),next_attempt_at:new Date(Date.now()+b*1000).toISOString(),updated_at:new Date().toISOString()}).eq('id',row.id).eq('status','processing');await db.from('notification_audit').insert({queue_id:row.id,user_id:row.user_id,event_name:row.event_name,action:'delivery',outcome:'failed',reason:msg.slice(0,500),metadata:{attempt,final}});failed++;}}
 return json({checked:rows?.length??0,delivered,failed},200,cors);
});