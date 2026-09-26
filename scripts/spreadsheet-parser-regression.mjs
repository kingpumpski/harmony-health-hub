import assert from 'node:assert/strict';
import XLSX from 'xlsx';
import {
  MAX_SPREADSHEET_FILE_BYTES,
  MAX_SPREADSHEET_ROWS,
  assertSupportedSpreadsheetFile,
  normalizeSpreadsheetRows,
  parseSpreadsheetBuffer,
} from '../src/lib/spreadsheetImport.mjs';

const makeWorkbook = (rows) => {
  const sheet = XLSX.utils.json_to_sheet(rows);
  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, sheet, 'Import');
  return XLSX.write(workbook, { type: 'buffer', bookType: 'xlsx' });
};

const run = async () => {
  const workbook = makeWorkbook([
    { ' First Name ': ' Ama ', 'LAST_NAME': ' Mensah ', Amount: 12.5, Empty: '' },
    { ' First Name ': 'Kojo', 'LAST_NAME': 'Asare', Amount: 0, Empty: null },
  ]);

  const rows = await parseSpreadsheetBuffer(workbook, 'patients.XLSX');
  assert.deepEqual(rows, [
    { 'first name': 'Ama', last_name: 'Mensah', amount: 12.5, empty: null },
    { 'first name': 'Kojo', last_name: 'Asare', amount: 0, empty: null },
  ]);

  assert.deepEqual(
    normalizeSpreadsheetRows([{ ' CODE ': ' GH-001 ', ACTIVE: true, Count: 0, Empty: undefined }]),
    [{ code: 'GH-001', active: true, count: 0, empty: null }],
  );

  assert.doesNotThrow(() => assertSupportedSpreadsheetFile('legacy.xls', 1024));
  assert.doesNotThrow(() => assertSupportedSpreadsheetFile('legacy.xlsx', 1024));
  assert.throws(() => assertSupportedSpreadsheetFile('legacy.csv', 1024), /Choose XLSX or XLS/);
  assert.throws(
    () => assertSupportedSpreadsheetFile('legacy.xlsx', MAX_SPREADSHEET_FILE_BYTES + 1),
    /Imports are limited/,
  );

  const oversized = makeWorkbook(
    Array.from({ length: MAX_SPREADSHEET_ROWS + 1 }, (_, index) => ({
      row_number: index + 1,
      value: 'oversized',
    })),
  );
  await assert.rejects(
    () => parseSpreadsheetBuffer(oversized, 'oversized.xlsx'),
    /Imports are limited to 10,000 rows/,
  );

  await assert.rejects(
    () => parseSpreadsheetBuffer(workbook, 'unsupported.csv'),
    /Choose XLSX or XLS/,
  );

  console.log('Spreadsheet parser regression checks passed.');
};

await run();
