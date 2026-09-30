import fs from 'node:fs';
import path from 'node:path';
const dir=path.join(process.cwd(),'supabase','migrations'); const files=fs.readdirSync(dir).filter(f=>f.endsWith('.sql')).sort(); const failures=[];
for(const name of files){const source=fs.readFileSync(path.join(dir,name),'utf8').replace(/--.*$/gm,''); for(const m of source.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+((?:public|private)\.[a-zA-Z_][a-zA-Z0-9_]*)[\s\S]*?SECURITY\s+DEFINER[\s\S]*?(?=CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+|$)/gi)){const b=m[0]; if(/GRANT\s+EXECUTE\s+ON\s+FUNCTION[^;]+\s+TO\s+(?:PUBLIC|anon)/i.test(b)) failures.push(name+': '+m[1]+' exposes SECURITY DEFINER execution publicly');}}
if(failures.length){console.error('Public SECURITY DEFINER exposure contract failed:\n'+failures.join('\n'));process.exitCode=1}else console.log('Public SECURITY DEFINER exposure contract passed.');
