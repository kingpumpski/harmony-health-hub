import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

type Channel = 'in_app'|'email'|'sms'|'push'|'whatsapp'|'voice';
const BATCH=50, BACKOFF=[10,30,120,600,3600];
const json=(body:unknown,status=200,cors:Record<string,string>={})=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});

function b64url(data:Uint8Array|string){const bytes=typeof data==='string'?new TextEncoder().encode(data):data;let s='';for(const b of bytes)s+=String.fromCharCode(b);return btoa(s).replace(/\+/g,'-').replace(/\//g/g,'_').replace(/=+$/,'');}
let fcmAccessToken:{token:string;expires:number}|null=null;
async function fcmToken(){
  if(fcmAccessToken&&fcmAccessToken.expires>Date.now()+60000)return fcmAccessToken.token;
  const raw=Deno.env.get('FCM_SERVICE_ACCOUNT_JSON'); if(!raw)throw new Error('FCM service account not configured');
  const sa=JSON.parse(raw); const now=Math.floor(Date.now()/1000);
  const header=b64url(JSON.stringify({alg:'RS256',typ:'JWT'}));
  const claim=b64url(JSON.stringify({iss:sa.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600}));
  const pem=sa.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\\s/g,'');
  const bin=Uint8Array.from(atob(pem),c=>c.charCodeAt(0));
  const key=await crypto.subtle.importKey('pkcs8',bin,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const sig=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(header+'.'+claim));
  const assertion=header+'.'+claim+'.'+b64url(new Uint8Array(sig));
  const tokenRes=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion})});
  const token=await tokenRes.json(); if(!tokenRes.ok||!token.access_token)throw new Error('FCM OAuth token request failed');
  fcmAccessToken={token:token.access_token,expires:Date.now()+Number(token.expires_in??3600)*1000}; return token.access_token;
}
async function external(channel:Channel, recipient:{email?:string;phone?:string;deviceTokens?:string[]}, subject:string, body:string, payload:Record<string,unknown>={}){
  if(channel==='email'){
    if(!recipient.email)return {ok:false,provider:'none',error:'Recipient email unavailable'};
    const key=Deno.env.get('RESEND_API_KEY'),from=Deno.env.get('RESEND_FROM_EMAIL');
    if(!key||!from)return {ok:false,provider:'resend',error:'Resend provider not configured'};
    const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{authorization:`Bearer ${key}`,'content-type':'application/json'},body:JSON.stringify({from,to:[recipient.email],subject,html:`<div style="font-family:Arial,sans-serif;line-height:1.5"><h2>${subject}</h2><p>${body.replace(/\n/g,'<br/>')}</p></div>`,text:body})});
    const d=await r.json().catch(()=>({})); return {ok:r.ok,provider:'resend',id:d.id,error:r.ok?undefined:String(d.message??d.name??'Resend error')};
  }
  if(channel==='push'){
    const tokens=recipient.deviceTokens??[]; if(!tokens.length)return {ok:false,provider:'fcm',error:'No active FCM device token'};
    const project=Deno.env.get('FCM_PROJECT_ID'); if(!project)return {ok:false,provider:'fcm',error:'FCM project not configured'};
    const access=await fcmToken(); let sent=0,last='';
    for(const token of tokens){
      const r=await fetch(`https://fcm.googleapis.com/v1/projects/${project}/messages:send`,{method:'POST',headers:{authorization:`Bearer ${access}`,'content-type':'application/json'},body:JSON.stringify({message:{token,notification:{title:subject,body},data:{event_name:String(payload.event_name??''),queue_id:String(payload.queue_id??''),link:String(payload.link??'')}}})});
      const d=await r.json().catch(()=>({})); if(r.ok)sent++; else last=String(d.error?.message??'FCM send failed');
    }
    return {ok:sent>0,provider:'fcm',id:sent?String(sent):undefined,error:sent?undefined:last||'FCM send failed'};
  }
  const account=Deno.env.get('TWILIO_ACCOUNT_SID'),token=Deno.env.get('TWILIO_AUTH_TOKEN');
  if(!account||!token||!recipient.phone)return {ok:false,provider:'twilio',error:'Twilio recipient/provider not configured'};
  if(channel==='sms'||channel==='whatsapp'){
    const from=channel==='whatsapp'?Deno.env.get('TWILIO_WHATSAPP_FROM'):Deno.env.get('TWILIO_SMS_FROM');
    if(!from)return {ok:false,provider:'twilio',error:'Twilio sender not configured'};
    const to=channel==='whatsapp'?`whatsapp:${recipient.phone}`:recipient.phone;
    const params:Record<string,string>={To:to,From:from};
    if(channel==='whatsapp'){
      const contentSid=Deno.env.get('TWILIO_WHATSAPP_CONTENT_SID');
      if(contentSid){params.ContentSid=contentSid;params.ContentVariables=JSON.stringify(payload.whatsapp_variables??{'1':String(payload.date??''),'2':String(payload.time??'')});}
      else params.Body=body;
    } else params.Body=body;
    const form=new URLSearchParams(params),auth=btoa(`${account}:${token}`);
    const callback=Deno.env.get('NOTIFICATION_WEBHOOK_PUBLIC_URL'); if(callback)form.set('StatusCallback',callback);
    const r=await fetch(`https://api.twilio.com/2010-04-01/Accounts/${account}/Messages.json`,{method:'POST',headers:{authorization:`Basic ${auth}`,'content-type':'application/x-www-form-urlencoded'},body:form});
    const d=await r.json().catch(()=>({})); return {ok:r.ok,provider:'twilio',id:d.sid,error:r.ok?undefined:String(d.message??d.error_message??'Provider error')};
  }
  if(channel==='voice'){
    const from=Deno.env.get('TWILIO_VOICE_FROM'),url=Deno.env.get('TWILIO_VOICE_TWIML_URL');
    if(!from||!url)return {ok:false,provider:'twilio',error:'Voice sender or TwiML URL not configured'};
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
   const userId=row.user_id??p.user_id;const [{data:profile},{data:prefs},{data:event},{data:devices}]=await Promise.all([
    db.from('profiles').select('email,phone').eq('id',userId).maybeSingle(),
    db.from('user_notification_preferences').select('*').eq('user_id',userId).maybeSingle(),
    db.from('notification_events').select('*').eq('event_name',row.event_name).maybeSingle(),
    db.from('notification_devices').select('token').eq('user_id',userId).eq('provider','fcm').eq('active',true)
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
    const r=await external(channel,{email:profile.email??undefined,phone:profile.phone??undefined,deviceTokens:(devices??[]).map((d:any)=>d.token)},String(p.subject??p.title??'Health notification'),String(p.message??'Please sign in to your secure health record.'),{...p,event_name:row.event_name,queue_id:row.id});
    await db.from('notification_delivery_logs').insert({queue_id:row.id,user_id:userId,channel,provider:r.provider,status:r.ok?'sent':'failed',provider_message_id:r.id??null,attempt,latency_ms:Date.now()-started,error_message:r.error??null});
    if(r.ok){ok=true;break;}last=r.error??last;
   }
   if(!ok)throw new Error(last);
   await db.from('notification_queue').update({status:'delivered',attempts:attempt,delivered_at:new Date().toISOString(),last_error:null,updated_at:new Date().toISOString()}).eq('id',row.id).eq('status','processing');delivered++;
 }catch(err){const msg=err instanceof Error?err.message:String(err),max=row.max_attempts??5,final=attempt>=max,b=BACKOFF[Math.min(attempt-1,BACKOFF.length-1)];await db.from('notification_queue').update({status:final?'failed':'pending',attempts:attempt,last_error:msg.slice(0,500),next_attempt_at:new Date(Date.now()+b*1000).toISOString(),updated_at:new Date().toISOString()}).eq('id',row.id).eq('status','processing');await db.from('notification_audit').insert({queue_id:row.id,user_id:row.user_id,event_name:row.event_name,action:'delivery',outcome:'failed',reason:msg.slice(0,500),metadata:{attempt,final}});failed++;}}
 return json({checked:rows?.length??0,delivered,failed},200,cors);
});