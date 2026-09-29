#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const dir = path.join(process.cwd(), "supabase", "migrations");
function walk(d, out = []) {
  if (!fs.existsSync(d)) return out;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const f = path.join(d, e.name);
    if (e.isDirectory()) walk(f, out);
    else if (e.name.endsWith(".sql")) out.push(f);
  }
  return out;
}

const files = walk(dir);
const source = files.map((f) => fs.readFileSync(f, "utf8")).join("\n").replace(/--.*$/gm, "");
const declarations = [...source.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+public\.([a-zA-Z0-9_]+)/gi)];
const views = [...new Set(declarations.map((m) => m[1]))];
const failures = [];

for (const view of views) {
  const escaped = view.replace(/[.*+?^$()|[\]\\]/g, "\\$&");
  const invoker = new RegExp(
    "(?:ALTER\\s+VIEW\\s+public\\." + escaped +
    "[\\s\\S]*?security_invoker\\s*=\\s*true|CREATE\\s+(?:OR\\s+REPLACE\\s+)?VIEW\\s+public\\." +
    escaped + "[\\s\\S]*?security_invoker\\s*=\\s*true)",
    "i",
  );
  const revoked = new RegExp(
    "REVOKE\\s+(?:ALL|SELECT)[\\s\\S]*?ON\\s+(?:VIEW\\s+)?public\\." +
    escaped + "\\s+FROM\\s+(?:PUBLIC|anon|authenticated)",
    "i",
  );
  if (!invoker.test(source) && !revoked.test(source)) {
    failures.push(view + ": public view lacks security_invoker=true or explicit Data API privilege revocation");
  }
}

assert.equal(failures.length, 0, "Public view security contract failed:\n" + failures.join("\n"));
console.log("Public view security contract passed for " + views.length + " public views.");
