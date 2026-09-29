import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const root = process.cwd();
const migrationsDir = path.join(root, "supabase", "migrations");
const manifestPath = path.join(root, "scripts", "function-privilege-manifest.json");

assert.ok(fs.existsSync(manifestPath), "function privilege manifest must exist");

const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
assert.equal(manifest.version, 1);
assert.equal(manifest.scope, "selected-high-risk-function-execute-contract");

const files = fs.existsSync(migrationsDir)
  ? fs.readdirSync(migrationsDir).filter((n) => n.endsWith(".sql")).sort()
  : [];

const source = files
  .map((n) => fs.readFileSync(path.join(migrationsDir, n), "utf8"))
  .join("\n")
  .replace(/--.*$/gm, "");

const compact = (s) => s.replace(/\s+/g, "").toLowerCase();

function splitParameters(value) {
  const parts = [];
  let start = 0;
  let depth = 0;
  let quote = null;

  for (let i = 0; i < value.length; i += 1) {
    const ch = value[i];
    if (quote) {
      if (ch === quote && value[i - 1] !== "\\") quote = null;
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      continue;
    }
    if (ch === "(") depth += 1;
    else if (ch === ")") depth -= 1;
    else if (ch === "," && depth === 0) {
      parts.push(value.slice(start, i).trim());
      start = i + 1;
    }
  }

  const tail = value.slice(start).trim();
  if (tail) parts.push(tail);
  return parts;
}

function normalizeParameter(parameter) {
  let value = parameter
    .replace(/\b(?:INOUT|IN|OUT|VARIADIC)\b/gi, "")
    .replace(/\bDEFAULT\b[\s\S]*$/i, "")
    .replace(/=[\s\S]*$/i, "")
    .trim();

  // Migration declarations conventionally name parameters with identifiers such
  // as _patient_id. Strip that identifier, then compare the exact PostgreSQL type.
  value = value.replace(/^[a-zA-Z_][a-zA-Z0-9_]*\\s+/, "").trim();

  return value.replace(/\\s+/g, " ").toLowerCase();
}

function signatureTypes(signature) {
  return signature.split(",").map((value) => value.trim().toLowerCase());
}

const declarations = new Map();

for (const name of Object.keys(manifest.functions)) {
  const escaped = name.replace(/[.*+?^$()|[\\]\\\\]/g, "\\$&");
  const re = new RegExp(
    "CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\." +
      escaped +
      "\\s*\\(([\s\S]*?)\\)",
    "gi",
  );

  const signatures = [];
  for (const match of source.matchAll(re)) {
    const params = splitParameters(match[1]);
    signatures.push(params.map(normalizeParameter));
  }
  declarations.set(name, signatures);
}

const sql = compact(source);

for (const [name, spec] of Object.entries(manifest.functions)) {
  assert.ok(
    Array.isArray(spec.signatures) && spec.signatures.length > 0,
    name + ": signatures required",
  );
  assert.deepEqual(
    spec.allowed_execute_roles,
    ["authenticated"],
    name + ": selected contract must remain authenticated-only",
  );

  const declared = declarations.get(name) ?? [];
  assert.ok(
    declared.length > 0,
    name + ": function declaration must exist in migration history",
  );

  for (const signature of spec.signatures) {
    const expectedTypes = signatureTypes(signature);
    assert.ok(
      declared.some((actualTypes) =>
        actualTypes.length === expectedTypes.length &&
        actualTypes.every((type, index) => type === expectedTypes[index]),
      ),
      name +
        ": manifest signature " +
        signature +
        " does not match any declared PostgreSQL parameter type signature (" +
        declared.map((types) => types.join(",")).join(" | ") +
        ")",
    );

    const qualified = `public.${name}(${signature})`;

    assert.ok(
      sql.includes(compact(`grant execute on function ${qualified} to authenticated;`)),
      qualified + " must have an explicit authenticated EXECUTE grant",
    );

    if (spec.requires_public_revoke) {
      assert.ok(
        sql.includes(compact(`revoke all on function ${qualified} from public;`)) ||
          sql.includes(compact(`revoke execute on function ${qualified} from public;`)),
        qualified + " must explicitly revoke PUBLIC EXECUTE",
      );
    }

    if (spec.requires_anon_revoke) {
      assert.ok(
        sql.includes(compact(`revoke all on function ${qualified} from public, anon;`)) ||
          sql.includes(compact(`revoke execute on function ${qualified} from anon;`)) ||
          sql.includes(compact(`revoke all on function ${qualified} from anon;`)),
        qualified + " must explicitly revoke anon EXECUTE",
      );
    }
  }
}

console.log(
  `[function-privilege] checked ${Object.keys(manifest.functions).length} selected high-risk RPCs with exact PostgreSQL parameter-type signatures`,
);
