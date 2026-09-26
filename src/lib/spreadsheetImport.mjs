export const MAX_SPREADSHEET_FILE_BYTES = 25 * 1024 * 1024;
export const MAX_SPREADSHEET_ROWS = 10_000;
export const SUPPORTED_SPREADSHEET_EXTENSIONS = ['.xlsx', '.xls'];

export const normalizeSpreadsheetCell = (value) => {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value === 'boolean' || typeof value === 'number') return value;
  return String(value).trim();
};

export const normalizeSpreadsheetRows = (data) =>
  data.map((row) =>
    Object.fromEntries(
      Object.entries(row).map(([key, value]) => [
        key.trim().toLowerCase(),
        normalizeSpreadsheetCell(value),
      ]),
    ),
  );

export const assertSupportedSpreadsheetFile = (fileName, byteLength) => {
  if (byteLength > MAX_SPREADSHEET_FILE_BYTES) {
    throw new Error(`Imports are limited to ${MAX_SPREADSHEET_FILE_BYTES / 1024 / 1024} MB.`);
  }

  const lowerName = fileName.toLowerCase();
  if (!SUPPORTED_SPREADSHEET_EXTENSIONS.some((extension) => lowerName.endsWith(extension))) {
    throw new Error('Choose XLSX or XLS.');
  }
};

export const parseSpreadsheetBuffer = async (buffer, fileName) => {
  assertSupportedSpreadsheetFile(fileName, buffer.byteLength);

  const XLSX = await import('xlsx');
  const workbook = XLSX.read(buffer, {
    type: 'array',
    dense: true,
    cellFormula: false,
    bookVBA: false,
  });

  const sheetName = workbook.SheetNames[0];
  if (!sheetName) throw new Error('The workbook contains no worksheets.');

  const data = XLSX.utils.sheet_to_json(workbook.Sheets[sheetName], {
    defval: null,
    raw: true,
  });

  if (data.length > MAX_SPREADSHEET_ROWS) {
    throw new Error(`Imports are limited to ${MAX_SPREADSHEET_ROWS.toLocaleString()} rows.`);
  }

  return normalizeSpreadsheetRows(data);
};
