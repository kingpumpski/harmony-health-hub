import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { buildCorsHeaders, handlePreflight } from '../_shared/cors.ts';

const json=(body:unknown,status=200,cors:Record<string,string>={})=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});

async function hmac(secret:string,message:string,hash='SHA-256',base64Secret=false){
  const material=base64Secret?Uint8Array.from(atob(secret),c=>c.charCodeAt(0)):new TextEncoder().encode(secret);
  const key=await crypto.subtle.importKey('raw',material,{name:'HMAC',hash},false,['sign']);
  const sig=await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(message));
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}
function parseSvix(value:string){return value.split(' ').map(x=>x.startsWith('v1,')?x.slice(3):x).filter(Boolean);}

Deno.serve(async req=>{
  const pre=handlePreflight(req); if(pre)return pre;
  const cors=buildCorsHeaders(req);
  if(req.method!=='POST')return json({error:'METHOD_NOT_ALLOWED'},405,cors);

  const provider=req.headers.get('x-notification-provider')??'';
  const raw=await req.text();
  const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  let eventId='',eventType='',payload:Record<string,any>={};
  if(provider==='resend'){
    const secret=Deno.env.get('RESEND_WEBHOOK_SECRET');
    const svixId=req.headers.get('svix-id')??'',timestamp=req.headers.get('svix-timestamp')??'',signature=req.headers.get('svix-signature')??'';
    if(!secret||!svixId||!timestamp||!signature)return json({error:'INVALID_WEBHOOK'},401,cors);
    const timestampSeconds=Number(timestamp);
    if(!Number.isFinite(timestampSeconds) || Math.abs(Math.floor(Date.now()/1000)-timestampSeconds)>300){
      return json({error:'STALE_WEBHOOK'},401,cors);
    }
    const signingSecret=secret.replace(/^whsec_/,'');
    const expected=await hmac(signingSecret,svixId+'.'+timestamp+'.'+raw,'SHA-256',true);
    const signatures=parseSvix(signature);
    if(!signatures.some(s=>s===expected))return json({error:'INVALID_SIGNATURE'},401,cors);
    let parsed:Record<string,any>;
    try { parsed=JSON.parse(raw); } catch { return json({error:'INVALID_JSON'},400,cors); }
    eventId=svixId; eventType=String(parsed.type??''); payload=parsed;
  } else if(provider==='twilio'){
    const authToken=Deno.env.get('TWILIO_AUTH_TOKEN');
    const signature=req.headers.get('x-twilio-signature');
    const publicUrl=Deno.env.get('NOTIFICATION_WEBHOOK_PUBLIC_URL');
    if(!authToken||!signature||!publicUrl)return json({error:'TWILIO_WEBHOOK_NOT_CONFIGURED'},503,cors);
    const params=new URLSearchParams(raw);
    const data=[...params.entries()].sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>k+v).join('');
    const expected=await hmac(authToken,publicUrl+data,'SHA-1',false);
    if(expected!==signature)return json({error:'INVALID_SIGNATURE'},401,cors);
    eventId=params.get('MessageSid')??params.get('CallSid')??crypto.randomUUID();
    eventType=params.get('MessageStatus')??params.get('CallStatus')??'received';
    payload=Object.fromEntries(params.entries());
  } else return json({error:'UNSUPPORTED_PROVIDER'},400,cors);

  const {data:inserted,error:insertError}=await db.from('notification_webhook_events')
    .insert({provider,external_event_id:eventId,event_type:eventType,payload})
    .select('id').maybeSingle();
  if(insertError?.code==='23505')return json({ok:true,duplicate:true},200,cors);
  if(insertError)return json({error:'WEBHOOK_STORE_FAILED'},500,cors);

  if(provider==='resend' && eventType==='email.received'){
    const d=payload?.data??{};
    await db.from('notification_inbound_emails').upsert({provider:'resend',provider_message_id:String(d.email_id??d.id??'')||null,message_id:String(d.message_id??d.email_id??d.id??'')||null,from_address:typeof d.from==='string'?d.from:null,to_addresses:Array.isArray(d.to)?d.to:[],cc_addresses:Array.isArray(d.cc)?d.cc:[],subject:typeof d.subject==='string'?d.subject:null,text_body:typeof d.text==='string'?d.text:null,html_body:typeof d.html==='string'?d.html:null,attachments:Array.isArray(d.attachments)?d.attachments:[],received_at:new Date().toISOString(),raw_event:payload,processing_status:'received'},{onConflict:'provider,provider_message_id'});
  }
  const externalId=String(payload?.data?.email_id??payload?.data?.id??payload?.MessageSid??payload?.CallSid??'');
  if(externalId){
    const statusMap:Record<string,string>={
      'email.sent':'sent','email.delivered':'delivered','email.delivery_delayed':'failed',
      'email.bounced':'bounced','email.complained':'failed','email.opened':'read','email.clicked':'clicked',
      queued:'queued',sent:'sent',delivered:'delivered',read:'read',failed:'failed',undelivered:'failed'
    };
    const status=statusMap[eventType]??statusMap[String(payload?.data?.event??'')];
    if(status) await db.from('notification_delivery_logs').update({
      status,
      delivered_at:status==='delivered'?new Date().toISOString():undefined,
      read_at:status==='read'?new Date().toISOString():undefined,
      clicked_at:status==='clicked'?new Date().toISOString():undefined
    }).eq('provider_message_id',externalId);
  }
  await db.from('notification_webhook_events').update({processed_at:new Date().toISOString()}).eq('id',inserted.id);
  return json({ok:true},200,cors);
});
