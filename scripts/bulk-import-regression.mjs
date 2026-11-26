import assert from 'node:assert/strict';
import { parseDate, parseNumber, canonicalHeader, rowsFromMatrix, prepareImport, withRetry, chunk } from '../src/lib/bulkImport.mjs';

assert.equal(parseDate('12/04/1990'), '1990-04-12', 'DD/MM/YYYY');
assert.equal(parseDate('1990-04-12'), '1990-04-12');
assert.equal(parseDate(32975), '1990-04-12', 'Excel serial');
assert.equal(parseDate('31/02/2020'), null, 'impossible date rejected');
assert.equal(parseDate('5 Mar 2021'), '2021-03-05');
assert.equal(parseNumber('GHS 1,250.50'), 1250.5);
assert.equal(parseNumber('abc'), null);
assert.equal(canonicalHeader('First Name*', 'patients'), 'first_name');
assert.equal(canonicalHeader('Surname', 'patients'), 'last_name');
assert.equal(canonicalHeader('\uFEFFDOB', 'patients'), 'date_of_birth');

const matrix = [
  ['Patients import template'], [],
  ['First Name', 'Surname', 'DOB', 'Sex', 'Email', 'Shoe size'],
  ['Jane', 'Doe', '12/04/1990', 'F', 'JANE@x.com', '7'],
  [null, null, null, null, null, null],
  ['Jane', 'Doe', '1990-04-12', 'female', '', ''],
  ['Kofi', '', '01/01/1980', 'M', '', ''],
  ['Ama', 'Mensah', '99/99/99', 'X', 'bad', ''],
];
const { headers, rows } = rowsFromMatrix(matrix, 'patients');
assert.equal(rows.length, 4, 'title and blank rows skipped');
const res = prepareImport('patients', rows, headers);
assert.equal(res.valid.length, 1);
assert.deepEqual({ ...res.valid[0], __row: undefined }, { first_name: 'Jane', last_name: 'Doe', date_of_birth: '1990-04-12', gender: 'female', email: 'jane@x.com', __row: undefined });
assert.equal(res.duplicates, 1, 'in-file duplicate detected');
assert.ok(res.issues.some((i) => i.row === 7 && /last_name is required/.test(i.reason)));
assert.ok(res.issues.some((i) => i.row === 8 && /date/.test(i.reason) && /gender/.test(i.reason) && /email/.test(i.reason)));
assert.deepEqual(res.ignoredColumns, ['shoe_size']);
assert.throws(() => rowsFromMatrix([['foo', 'bar']], 'patients'), /header row/);

const inv = prepareImport('pharmacy_inventory', [{ sourceRow: 2, data: { drug_name: 'Paracetamol', stock_quantity: '-5' } }], ['drug_name', 'stock_quantity']);
assert.equal(inv.valid.length, 0, 'negative stock rejected');

assert.equal(chunk([1, 2, 3, 4, 5], 2).length, 3);
let calls = 0;
assert.equal(await withRetry(async () => { calls++; if (calls < 3) throw new Error('net'); return 'ok'; }, { baseMs: 1 }), 'ok');
calls = 0;
await assert.rejects(withRetry(async () => { calls++; throw new Error('perm'); }, { baseMs: 1, isRetryable: () => false }));
assert.equal(calls, 1, 'non-retryable not retried');
console.log('bulk-import regression: all checks passed');
