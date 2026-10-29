#!/usr/bin/env node
/**
 * Validate PostgreSQL dollar-quoted blocks in Supabase migrations.
 *
 * Ignores SQL single-quoted strings and comments. For each dollar-quote opener,
 * requires the identical closing delimiter; reports the migration and line.
 */
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const migrationsDir = path.join(root, 'supabase', 'migrations');

async function listSqlFiles(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...await listSqlFiles(fullPath));
    else if (entry.isFile() && entry.name.endsWith('.sql')) files.push(fullPath);
  }
  return files;
}

function lineAt(source, offset) {
  let line = 1;
  for (let i = 0; i < offset; i += 1) if (source[i] === '\n') line += 1;
  return line;
}

function validate(source, file) {
  const errors = [];
  let i = 0;
  while (i < source.length) {
    if (source.startsWith('--', i)) {
      const end = source.indexOf('\n', i + 2);
      i = end === -1 ? source.length : end + 1;
      continue;
    }
    if (source.startsWith('/*', i)) {
      const start = i;
      let depth = 1;
      i += 2;
      while (i < source.length && depth > 0) {
        if (source.startsWith('/*', i)) { depth += 1; i += 2; }
        else if (source.startsWith('*/', i)) { depth -= 1; i += 2; }
        else i += 1;
      }
      if (depth > 0) errors.push(`${file}:${lineAt(source, start)}: unterminated block comment`);
      continue;
    }
    if (source[i] === "'") {
      const start = i++;
      let closed = false;
      while (i < source.length) {
        if (source[i] === "'" && source[i + 1] === "'") { i += 2; continue; }
        if (source[i] === "'") { i += 1; closed = true; break; }
        if (source[i] === '\\' && i + 1 < source.length) { i += 2; continue; }
        i += 1;
      }
      if (!closed) errors.push(`${file}:${lineAt(source, start)}: unterminated single-quoted SQL string`);
      continue;
    }
    if (source[i] === '$') {
      if (source.startsWith('$;', i)) {
        errors.push(`${file}:${lineAt(source, i)}: stray single-dollar terminator "$;" is prohibited; close the block with its matching dollar-quote delimiter`);
        i += 2;
        continue;
      }
      const match = source.slice(i).match(/^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/);
      if (match) {
        const delimiter = match[0];
        const start = i;
        const bodyStart = i + delimiter.length;
        const close = source.indexOf(delimiter, bodyStart);
        if (close === -1) {
          errors.push(`${file}:${lineAt(source, start)}: unterminated dollar-quoted block opened with ${delimiter}; expected matching ${delimiter}`);
          return errors;
        }
        i = close + delimiter.length;
        continue;
      }
    }
    i += 1;
  }
  return errors;
}

let files;
try {
  files = (await listSqlFiles(migrationsDir)).sort();
} catch (error) {
  console.error(`Unable to scan migration directory ${migrationsDir}: ${error.message}`);
  process.exit(2);
}

const failures = [];
for (const file of files) {
  const source = await readFile(file, 'utf8');
  failures.push(...validate(source, path.relative(root, file)));
}

if (failures.length) {
  console.error('PL/pgSQL dollar-quote validation failed:');
  for (const failure of failures) console.error(` - ${failure}`);
  process.exit(1);
}
console.log(`PL/pgSQL dollar-quote validation passed for ${files.length} migration file(s).`);
