import assert from "node:assert/strict";
import fs from "node:fs";

const sourceIndex = fs.readFileSync("src/lib/mcp/index.ts", "utf8");
const sourceClient = fs.readFileSync("src/lib/mcp/supabase.ts", "utf8");
const edge = fs.readFileSync("supabase/functions/mcp/index.ts", "utf8");
for (const [name, content] of [["MCP source", sourceIndex], ["MCP client", sourceClient], ["generated MCP Edge Function", edge]]) {
  assert.doesNotMatch(content, /pmebpkcufyrbjhawsiyn|eyJhbGciOiJIUzI1NiIs/, name + " must not contain the unowned development project or its embedded key");
  assert.doesNotMatch(content, /SUPABASE_SERVICE_ROLE_KEY/, name + " must not use a service-role credential for user-scoped read tools");
}
assert.match(sourceIndex, /Deno\?\.env\.get\("SUPABASE_URL"\)/, "MCP issuer must use the configured server URL");
assert.match(sourceIndex, /if \(!supabaseUrl\) throw new Error/, "missing Supabase URL must fail closed");
assert.ok(sourceIndex.includes('const authIssuer = supabaseUrl.replace'), "OAuth issuer must derive from the configured Supabase URL");
assert.ok(sourceIndex.includes('issuer: authIssuer'), "MCP must use its environment-derived OAuth issuer");
assert.match(sourceClient, /denoEnv\("SUPABASE_URL"\)/, "MCP Supabase URL must come from the Edge Function environment");
assert.match(sourceClient, /denoEnv\("SUPABASE_ANON_KEY"\)/, "MCP publishable key must come from the Edge Function environment");
assert.match(sourceClient, /if \(!token\) throw new Error/, "MCP requests must require a verified user OAuth token");
assert.match(edge, /var authIssuerUrl = denoEnv\("SUPABASE_URL"\)/, "generated Edge Function must derive the issuer from the configured Supabase URL");
assert.ok(edge.includes("issuer: authIssuer"), "generated Edge Function must use the environment-derived OAuth issuer");
assert.match(edge, /const url = denoEnv\("SUPABASE_URL"\)/, "generated Edge Function must not fall back to a development URL");
assert.match(edge, /const key = denoEnv\("SUPABASE_ANON_KEY"\)/, "generated Edge Function must not embed a publishable key");
console.log("[mcp-project-config] no development-project fallback, no embedded key, and user-scoped OAuth configuration required.");
