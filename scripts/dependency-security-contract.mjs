#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const root = process.cwd();
const packagePath = path.join(root, "package.json");
const lockPath = path.join(root, "package-lock.json");

assert.ok(fs.existsSync(packagePath), "package.json must exist");
assert.ok(fs.existsSync(lockPath), "package-lock.json must exist");

const pkg = JSON.parse(fs.readFileSync(packagePath, "utf8"));
const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"));

const required = {
  "@supabase/supabase-js": "2.109.0",
  "react-router-dom": "6.30.6",
  "react-router": "6.30.6",
  "@remix-run/router": "1.23.4",
};

const rootDeps = {
  ...(pkg.dependencies ?? {}),
  ...(pkg.devDependencies ?? {}),
};

for (const [name, version] of Object.entries(required)) {
  assert.equal(
    name === "react-router-dom" || name === "@supabase/supabase-js" ? rootDeps[name] : lock.packages[`node_modules/${name}`]?.version,
    name === "react-router-dom" ? "^6.30.6" : version,
    name + ": dependency must remain on the patched baseline",
  );
}

const locked = lock.packages;
assert.equal(locked["node_modules/@supabase/supabase-js"]?.version, "2.109.0");
assert.equal(locked["node_modules/react-router-dom"]?.version, "6.30.6");
assert.equal(locked["node_modules/react-router"]?.version, "6.30.6");
assert.equal(locked["node_modules/@remix-run/router"]?.version, "1.23.4");

const domDeps = locked["node_modules/react-router-dom"]?.dependencies ?? {};
assert.equal(domDeps["@remix-run/router"], "1.23.4");
assert.equal(domDeps["react-router"], "6.30.6");

const routerDeps = locked["node_modules/react-router"]?.dependencies ?? {};
assert.equal(routerDeps["@remix-run/router"], "1.23.4");

console.log("[dependency-security] Supabase JS is pinned to 2.109.0; React Router is pinned to the patched 6.30.6/1.23.4 baseline.");
