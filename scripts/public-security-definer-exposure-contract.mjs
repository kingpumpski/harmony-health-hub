#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const root = process.cwd();
const migrationsDir = path.join(root, "supabase", "migrations");

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith(".sql")) out.push(full);
  }
  return out;
}

const files = walk(migrationsDir);
const source = files.map((file) => fs.readFileSync(file, "utf8")).join("\n").replace(/--.*$/gm, "");
const declarations = [...source.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.([a-zA-Z0-9_]+)\s*\(/gi)];
const names = [...new Set(declarations.map((m) => m[1]))];

function blocks(name) {
  const escaped = name.replace(/[.*+?^$()|[\]\\]/g, "\\$&");
  const re = new RegExp(
    "CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\." + escaped +
    "\\s*\\([^)]*\\)[\\s\\S]*?(?=CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.|$)",
    "gi",
  );
  return [...source.matchAll(re)].map((m) => m[0]).filter((block) => /SECURITY\s+DEFINER/i.test(block));
}

const failures = [];
let publicDefiners = 0;

for (const name of names) {
  const defs = blocks(name);
  if (!defs.length) continue;
  publicDefiners += 1;

  for (const block of defs) {
    assert.match(block, /SET\s+search_path\s*=/i, name + ": public SECURITY DEFINER function must set an explicit search_path");

    const revoke = new RegExp(
      "REVOKE\\s+(?:ALL|EXECUTE)[\\s\\S]*?ON\\s+FUNCTION\\s+public\\." + name + "\\s*\\(",
      "i",
    );
    if (!revoke.test(source)) failures.push(name + ": no explicit EXECUTE revoke exists in migration history");

    const publicGrant = new RegExp(
      "GRANT\\s+EXECUTE[\\s\\S]*?ON\\s+FUNCTION\\s+public\\." + name +
      "\\s*\\([^;]*\\)\\s+TO\\s+PUBLIC", "i",
    );
    if (publicGrant.test(source)) failures.push(name + ": migration history grants EXECUTE to PUBLIC");

    const anonGrant = new RegExp(
      "GRANT\\s+EXECUTE[\\s\\S]*?ON\\s+FUNCTION\\s+public\\." + name +
      "\\s*\\([^;]*\\)\\s+TO\\s+anon", "i",
    );
    if (anonGrant.test(source)) failures.push(name + ": migration history grants EXECUTE to anon");
  }
}

assert.equal(failures.length, 0, "Public SECURITY DEFINER exposure contract failed:\n" + failures.join("\n"));
console.log(`Public SECURITY DEFINER exposure contract passed for ${publicDefiners} function names across ${files.length} migrations.`);
