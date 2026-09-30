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
const source = files
  .map((file) => fs.readFileSync(file, "utf8"))
  .join("\n")
  .replace(/--.*$/gm, "");

const functionRe =
  /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.([a-zA-Z0-9_]+)\s*\([^)]*\)[\s\S]*?(?=CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.|$)/gi;
const blocks = [...source.matchAll(functionRe)]
  .map((match) => ({ name: match[1], block: match[0] }))
  .filter(({ block }) => /SECURITY\s+DEFINER/i.test(block));

const names = [...new Set(blocks.map(({ name }) => name))];
const failures = [];

const revokePattern =
  /REVOKE\s+(?:ALL|EXECUTE)[\s\S]*?ON\s+FUNCTION\s+public\.([a-zA-Z0-9_]+)\s*\(/gi;
const publicGrantPattern =
  /GRANT\s+EXECUTE[\s\S]*?ON\s+FUNCTION\s+public\.([a-zA-Z0-9_]+)\s*\([^;]*\)\s+TO\s+PUBLIC/gi;
const anonGrantPattern =
  /GRANT\s+EXECUTE[\s\S]*?ON\s+FUNCTION\s+public\.([a-zA-Z0-9_]+)\s*\([^;]*\)\s+TO\s+anon/gi;
const searchPathAlterPattern =
  /ALTER\s+FUNCTION\s+public\.([a-zA-Z0-9_]+)\s*\([^;]*\)\s+SET\s+search_path\s*(?:=|TO)\s*([^;]+)/gi;

const revoked = new Set(
  [...source.matchAll(revokePattern)].map((match) => match[1].toLowerCase()),
);
const publicGranted = new Set(
  [...source.matchAll(publicGrantPattern)].map((match) => match[1].toLowerCase()),
);
const anonGranted = new Set(
  [...source.matchAll(anonGrantPattern)].map((match) => match[1].toLowerCase()),
);
const alteredSearchPaths = new Map();
for (const match of source.matchAll(searchPathAlterPattern)) {
  alteredSearchPaths.set(match[1].toLowerCase(), match[2].trim());
}

for (const { name, block } of blocks) {
  const key = name.toLowerCase();
  const definitionSearchPath = block.match(
    /SET\s+search_path\s*(?:=|TO)\s*([^;]+)/i,
  );
  const alteredSearchPath = alteredSearchPaths.get(key);
  const effectiveSearchPath = alteredSearchPath ?? definitionSearchPath?.[1] ?? "";

  assert.ok(
    effectiveSearchPath,
    name + ": public SECURITY DEFINER function must have an explicit search_path",
  );
  assert.ok(
    !/^['"]?public\s*['"]?$/i.test(effectiveSearchPath.trim()),
    name + ": public SECURITY DEFINER function must not use public-only search_path",
  );

  if (!revoked.has(key)) {
    failures.push(name + ": no explicit EXECUTE revoke exists in migration history");
  }
  if (publicGranted.has(key)) {
    failures.push(name + ": migration history grants EXECUTE to PUBLIC");
  }
  if (anonGranted.has(key)) {
    failures.push(name + ": migration history grants EXECUTE to anon");
  }
}

assert.equal(
  failures.length,
  0,
  "Public SECURITY DEFINER exposure contract failed:\n" + failures.join("\n"),
);
console.log(
  `Public SECURITY DEFINER exposure contract passed for ${names.length} function names across ${files.length} migrations.`,
);
