import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const dir=path.join(process.cwd(),"supabase","migrations");
const files=fs.readdirSync(dir).filter((name)=>/^\d{14}_.+\.sql$/.test(name));
const versions=new Map();
for(const file of files){
  const version=file.slice(0,14);
  const existing=versions.get(version);
  assert.equal(existing,undefined,`Duplicate Supabase migration version ${version}: ${existing ?? ""} and ${file}`);
  versions.set(version,file);
}
console.log(`[migration-filename-uniqueness] ${files.length} migration filenames have unique 14-digit versions`);
