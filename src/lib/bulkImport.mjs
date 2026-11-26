// Pure, dependency-free helpers that turn messy template files (CSV/XLSX)
// into clean, validated rows for the admin bulk import. Shared by the UI and tests.

export const IMPORT_SCHEMAS = {
  patients: {
    label: 'Patients',
    required: ['first_name', 'last_name'],
    optional: ['date_of_birth', 'gender', 'phone', 'email', 'address', 'city', 'ghana_card_number', 'blood_group', 'genotype', 'allergies', 'chronic_conditions', 'insurance_provider', 'insurance_number', 'emergency_contact_name', 'emergency_contact_phone'],
    types: { date_of_birth: 'date', email: 'email', gender: 'gender', phone: 'phone', emergency_contact_phone: 'phone' },
    sample: { first_name: 'Jane', last_name: 'Doe', date_of_birth: '1990-04-12', gender: 'female', phone: '+233200000000', email: 'jane@example.com', ghana_card_number: 'GHA-123456789-0' },
    dedupeKeys: [['ghana_card_number'], ['first_name', 'last_name', 'date_of_birth'], ['first_name', 'last_name', 'phone']],
  },
  pharmacy_inventory: {
    label: 'Pharmacy inventory & drugs',
    required: ['drug_name'],
    optional: ['generic_name', 'strength', 'form', 'stock_quantity', 'reorder_level', 'unit_price', 'supplier', 'batch_number', 'expiry_date'],
    types: { stock_quantity: 'int', reorder_level: 'int', unit_price: 'money', expiry_date: 'date' },
    sample: { drug_name: 'Paracetamol', generic_name: 'Acetaminophen', strength: '500mg', form: 'tablet', stock_quantity: 500, reorder_level: 50, unit_price: 0.5, supplier: 'MedSupply Ghana', expiry_date: '2027-12-31' },
    dedupeKeys: [['drug_name', 'strength', 'form', 'batch_number']],
  },
  icd_codes: {
    label: 'ICD-10 codes',
    required: ['code', 'description'],
    optional: ['version', 'category'],
    types: { code: 'upper' },
    sample: { code: 'A00', description: 'Cholera', version: 'ICD-10', category: 'Infectious' },
    dedupeKeys: [['code']],
  },
  staff: {
    label: 'Staff / user accounts',
    required: ['email', 'first_name', 'last_name', 'role'],
    optional: ['phone', 'department', 'specialization', 'onboarding'],
    types: { email: 'email', phone: 'phone', role: 'lower' },
    sample: { email: 'user@example.com', first_name: 'Jane', last_name: 'Doe', role: 'nurse', onboarding: 'invite', department: 'Maternity' },
    dedupeKeys: [['email']],
  },
};

// Common header spellings people use in real spreadsheets -> canonical column.
const ALIASES = {
  firstname: 'first_name', fname: 'first_name', givenname: 'first_name', forename: 'first_name',
  lastname: 'last_name', lname: 'last_name', surname: 'last_name', familyname: 'last_name',
  dob: 'date_of_birth', birthdate: 'date_of_birth', dateofbirth: 'date_of_birth',
  sex: 'gender', mobile: 'phone', telephone: 'phone', phonenumber: 'phone', tel: 'phone', contact: 'phone',
  emailaddress: 'email', mail: 'email', ghanacard: 'ghana_card_number', ghanacardno: 'ghana_card_number', nationalid: 'ghana_card_number',
  bloodgroup: 'blood_group', bloodtype: 'blood_group', insurer: 'insurance_provider', insurancecompany: 'insurance_provider',
  insuranceno: 'insurance_number', policynumber: 'insurance_number', nhisnumber: 'insurance_number',
  drug: 'drug_name', drugname: 'drug_name', medicine: 'drug_name', itemname: 'drug_name', generic: 'generic_name',
  quantity: 'stock_quantity', qty: 'stock_quantity', stock: 'stock_quantity', price: 'unit_price', unitcost: 'unit_price', cost: 'unit_price',
  expiry: 'expiry_date', expirydate: 'expiry_date', exp: 'expiry_date', batch: 'batch_number', batchno: 'batch_number',
  icd: 'code', icdcode: 'code', icd10: 'code', diagnosis: 'description', name: 'description',
};

export const canonicalHeader = (raw, entity) => {
  const base = String(raw ?? '').replace(/^\uFEFF/, '').replace(/\*/g, '').trim().toLowerCase();
  const snake = base.replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
  const schema = IMPORT_SCHEMAS[entity];
  const known = schema ? [...schema.required, ...schema.optional] : [];
  if (known.includes(snake)) return snake;
  const compact = snake.replace(/_/g, '');
  const alias = ALIASES[compact];
  if (alias && (!schema || known.includes(alias))) return alias;
  return snake;
};

const pad = (n) => String(n).padStart(2, '0');
const validYmd = (y, m, d) => {
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d ? `${y}-${pad(m)}-${pad(d)}` : null;
};

/** Accepts ISO, DD/MM/YYYY (Ghana/UK convention), Excel serial numbers and JS Dates. */
export const parseDate = (value) => {
  if (value === null || value === undefined || value === '') return null;
  if (value instanceof Date && !Number.isNaN(value.getTime())) return validYmd(value.getUTCFullYear(), value.getUTCMonth() + 1, value.getUTCDate());
  if (typeof value === 'number' || /^\d{4,5}(\.\d+)?$/.test(String(value).trim())) {
    const serial = Number(value);
    if (serial > 0 && serial < 80000) {
      const dt = new Date(Date.UTC(1899, 11, 30) + Math.floor(serial) * 86400000);
      return validYmd(dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate());
    }
    return null;
  }
  const s = String(value).trim();
  let m = s.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[T\s].*)?$/);
  if (m) return validYmd(+m[1], +m[2], +m[3]);
  m = s.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$/);
  if (m) { let y = +m[3]; if (y < 100) y += y > 30 ? 1900 : 2000; return validYmd(y, +m[2], +m[1]); }
  const months = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
  m = s.match(/^(\d{1,2})[\s-]([a-z]{3})[a-z]*[\s-,]+(\d{4})$/i);
  if (m && months.indexOf(m[2].toLowerCase()) >= 0) return validYmd(+m[3], months.indexOf(m[2].toLowerCase()) + 1, +m[1]);
  return null;
};

export const parseNumber = (value) => {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  const cleaned = String(value).replace(/(GHS|GH₵|₵|\$|USD|,|\s)/gi, '');
  if (!/^-?\d*\.?\d+$/.test(cleaned)) return null;
  return Number(cleaned);
};

const GENDERS = { m: 'male', male: 'male', man: 'male', f: 'female', female: 'female', woman: 'female', o: 'other', other: 'other' };

/** Coerces one cell. Returns { value } or { error }. */
export const coerceCell = (type, value) => {
  if (value === null || value === undefined || String(value).trim() === '') return { value: null };
  switch (type) {
    case 'date': { const d = parseDate(value); return d ? { value: d } : { error: `"${value}" is not a valid date (use YYYY-MM-DD or DD/MM/YYYY)` }; }
    case 'int': { const n = parseNumber(value); return n !== null && Number.isInteger(n) && n >= 0 ? { value: n } : { error: `"${value}" must be a whole number of 0 or more` }; }
    case 'money': { const n = parseNumber(value); return n !== null && n >= 0 ? { value: Math.round(n * 100) / 100 } : { error: `"${value}" must be an amount of 0 or more` }; }
    case 'email': { const e = String(value).trim().toLowerCase(); return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) ? { value: e } : { error: `"${value}" is not a valid email` }; }
    case 'gender': { const g = GENDERS[String(value).trim().toLowerCase()]; return g ? { value: g } : { error: `"${value}" is not a recognised gender (male/female/other)` }; }
    case 'phone': { const p = String(value).replace(/[^\d+]/g, ''); return p.replace(/\D/g, '').length >= 7 ? { value: p } : { error: `"${value}" is not a valid phone number` }; }
    case 'upper': return { value: String(value).trim().toUpperCase() };
    case 'lower': return { value: String(value).trim().toLowerCase() };
    default: return { value: String(value).trim() };
  }
};

const isBlankRow = (row) => Object.values(row).every((v) => v === null || v === undefined || String(v).trim() === '');

/**
 * Finds the header row in a 2D sheet (skips title/instruction rows above it) and
 * returns objects keyed by canonical column names.
 */
export const rowsFromMatrix = (matrix, entity) => {
  const schema = IMPORT_SCHEMAS[entity];
  const scan = Math.min(matrix.length, 15);
  let headerIdx = -1; let best = 0;
  for (let i = 0; i < scan; i++) {
    const cells = (matrix[i] ?? []).map((c) => canonicalHeader(c, entity));
    const hits = schema.required.filter((r) => cells.includes(r)).length;
    if (hits > best) { best = hits; headerIdx = i; }
  }
  if (headerIdx < 0) throw new Error(`Could not find the header row. The file must contain the columns: ${schema.required.join(', ')}.`);
  const headers = matrix[headerIdx].map((c) => canonicalHeader(c, entity));
  const out = [];
  for (let i = headerIdx + 1; i < matrix.length; i++) {
    const r = {}; headers.forEach((h, j) => { if (h) r[h] = matrix[i]?.[j] ?? null; });
    if (!isBlankRow(r)) out.push({ sourceRow: i + 1, data: r });
  }
  return { headers, rows: out };
};

const dedupeKey = (row, keys) => {
  const parts = keys.map((k) => (row[k] === null || row[k] === undefined ? '' : String(row[k]).trim().toLowerCase()));
  return parts.every((p) => p !== '') ? keys.join('|') + '=' + parts.join('|') : null;
};

/**
 * Validates and cleans rows. Returns valid rows (with sourceRow), per-row issues,
 * in-file duplicates and the columns that were ignored because they are unknown.
 */
export const prepareImport = (entity, rawRows, headers = []) => {
  const schema = IMPORT_SCHEMAS[entity];
  if (!schema) throw new Error('Unsupported import type');
  const known = new Set([...schema.required, ...schema.optional]);
  const missingColumns = schema.required.filter((c) => !headers.includes(c));
  const ignoredColumns = [...new Set(headers.filter((h) => h && !known.has(h)))];
  const valid = []; const issues = []; const seen = new Map();
  if (missingColumns.length) return { valid, issues: [{ row: 0, reason: `Missing required column(s): ${missingColumns.join(', ')}` }], missingColumns, ignoredColumns, duplicates: 0 };
  let duplicates = 0;
  for (const { sourceRow, data } of rawRows) {
    const clean = {}; const errs = [];
    for (const col of known) {
      const { value, error } = coerceCell(schema.types[col], data[col]);
      if (error) errs.push(`${col}: ${error}`); else if (value !== null) clean[col] = value;
    }
    for (const r of schema.required) if (clean[r] === undefined && !errs.some((e) => e.startsWith(r + ':'))) errs.push(`${r} is required`);
    if (errs.length) { issues.push({ row: sourceRow, reason: errs.join('; ') }); continue; }
    let dupOf = null;
    for (const keys of schema.dedupeKeys) { const k = dedupeKey(clean, keys); if (k && seen.has(k)) { dupOf = seen.get(k); break; } }
    if (dupOf) { duplicates++; issues.push({ row: sourceRow, reason: `Duplicate of row ${dupOf} in this file — skipped` }); continue; }
    for (const keys of schema.dedupeKeys) { const k = dedupeKey(clean, keys); if (k) seen.set(k, sourceRow); }
    valid.push({ ...clean, __row: sourceRow });
  }
  return { valid, issues, missingColumns, ignoredColumns, duplicates };
};

export const chunk = (items, size) => { const out = []; for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size)); return out; };

/** Retries transient failures (network / 5xx) with exponential backoff. */
export const withRetry = async (fn, { attempts = 3, baseMs = 600, isRetryable = () => true } = {}) => {
  let last;
  for (let i = 0; i < attempts; i++) {
    try { return await fn(i); } catch (e) { last = e; if (i === attempts - 1 || !isRetryable(e)) break; await new Promise((r) => setTimeout(r, baseMs * 2 ** i)); }
  }
  throw last;
};
