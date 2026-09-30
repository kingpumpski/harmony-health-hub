import { Clock3 } from 'lucide-react';

type Props={value:string;onChange:(value:string)=>void;label?:string;className?:string};

export default function ModernTimeField({value,onChange,label,className=''}:Props){
 const parts=value.split(':'); const hours=parts[0]||'00'; const minutes=parts[1]||'00';
 const set=(h:string,m:string)=>onChange(h.padStart(2,'0')+':'+m.padStart(2,'0'));
 return <label className={'block space-y-1.5 text-sm '+className}>{label&&<span>{label}</span>}<div className="flex h-11 items-center gap-1 rounded-xl border border-border bg-background px-2 shadow-sm focus-within:border-primary/50 focus-within:ring-2 focus-within:ring-primary/10"><Clock3 className="ml-1 h-4 w-4 text-primary"/><select aria-label={(label||'')+' hour'} value={hours} onChange={e=>set(e.target.value,minutes)} className="h-8 rounded-lg border-0 bg-muted px-2 text-sm font-semibold outline-none">{Array.from({length:24},(_,i)=>{const h=String(i).padStart(2,'0');return <option key={h} value={h}>{h}</option>})}</select><span className="font-semibold text-muted-foreground">:</span><select aria-label={(label||'')+' minute'} value={minutes} onChange={e=>set(hours,e.target.value)} className="h-8 rounded-lg border-0 bg-muted px-2 text-sm font-semibold outline-none">{Array.from({length:12},(_,i)=>{const m=String(i*5).padStart(2,'0');return <option key={m} value={m}>{m}</option>})}</select></div></label>;
}
