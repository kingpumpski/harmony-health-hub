const MAX_CLINICAL_MIGRATION_TEXT_BYTES = 25 * 1024 * 1024;
const FHIR_RESOURCE_TYPES = new Set([
  'Patient', 'Encounter', 'Observation', 'DiagnosticReport', 'Condition',
  'AllergyIntolerance', 'Immunization', 'MedicationRequest', 'MedicationStatement',
  'Appointment', 'Procedure', 'DocumentReference', 'Invoice', 'Claim', 'Coverage',
  'ServiceRequest', 'CarePlan', 'Composition', 'Practitioner', 'Organization',
]);

const first = (...values) => values.find((value) => value !== undefined && value !== null && value !== '');

const reference = (value) => {
  if (typeof value === 'string') return value;
  if (value && typeof value === 'object') return first(value.reference, value.display, value.identifier?.value, null);
  return null;
};

const formatDate = (value) => {
  if (!value) return null;
  const text = String(value).trim();
  // HL7 v2 dates commonly use YYYYMMDD[HHmmss]; convert only recognized forms.
  const match = /^(\d{4})(\d{2})(\d{2})(\d{2})?(\d{2})?(\d{2})?(?:\.\d+)?(?:[+-]\d{4})?$/.exec(text);
  if (match) {
    const [, year, month, day, hour = '00', minute = '00', second = '00'] = match;
    return `${year}-${month}-${day}T${hour}:${minute}:${second}.000Z`;
  }
  const timestamp = Date.parse(text);
  return Number.isNaN(timestamp) ? null : new Date(timestamp).toISOString();
};

const fhirSummary = (resource) =>
  first(resource.code?.text, resource.code?.coding?.[0]?.display, resource.name?.[0]?.text,
    resource.description, resource.title, resource.text?.div, resource.status, null);

const toCanonicalRow = (record, index, sourceSystem) => {
  const resourceType = first(record.resourceType, record.record_type, record.recordType, record.type, record.kind, 'legacy_record');
  const patientReference = first(
    reference(record.subject), reference(record.patient), record.source_patient_key,
    record.sourcePatientKey, record.patient_id, record.patientId,
    resourceType === 'Patient' ? record.id : null,
  );
  const sourceRecordId = first(record.source_record_id, record.sourceRecordId, record.id, record.identifier?.[0]?.value, `${resourceType}-${index + 1}`);
  const occurredAt = first(record.occurred_at, record.occurredAt, record.effectiveDateTime,
    record.effectiveInstant, record.issued, record.date, record.recordedDate,
    record.authoredOn, record.period?.start, record.meta?.lastUpdated);
  const author = first(reference(record.author), reference(record.performer?.[0]), reference(record.recorder), null);
  const department = first(reference(record.serviceProvider), record.department, record.service, null);
  const encounter = first(reference(record.encounter), record.encounter_reference, record.encounterReference, null);
  const summary = first(record.clinical_summary, record.clinicalSummary, record.summary,
    record.description, fhirSummary(record), null);

  return {
    source_system: String(first(record.source_system, record.sourceSystem, sourceSystem, 'Legacy system')).trim(),
    source_patient_key: patientReference === null ? null : String(patientReference).replace(/^Patient\//, ''),
    source_record_id: String(sourceRecordId),
    record_type: String(resourceType),
    occurred_at: formatDate(occurredAt),
    author_name: author === null ? null : String(author),
    department: department === null ? null : String(department),
    encounter_reference: encounter === null ? null : String(encounter),
    clinical_summary: summary === null ? null : String(summary).replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 4000),
    raw_record: record,
  };
};

const extractJsonRecords = (parsed) => {
  if (Array.isArray(parsed)) return parsed;
  if (!parsed || typeof parsed !== 'object') throw new Error('JSON import must contain an object, array, or FHIR Bundle.');
  if (parsed.resourceType === 'Bundle') {
    const entries = Array.isArray(parsed.entry) ? parsed.entry : [];
    const resources = entries.map((entry) => entry?.resource).filter((resource) => resource && typeof resource === 'object');
    if (!resources.length) throw new Error('FHIR Bundle contains no entry resources.');
    return resources;
  }
  if (parsed.resourceType && FHIR_RESOURCE_TYPES.has(parsed.resourceType)) return [parsed];
  for (const key of ['records', 'data', 'items', 'results']) {
    if (Array.isArray(parsed[key])) return parsed[key];
  }
  return [parsed];
};

const xmlElementToObject = (element) => {
  const result = {};
  for (const attribute of Array.from(element.attributes ?? [])) result[`@${attribute.name}`] = attribute.value;
  const children = Array.from(element.children ?? []);
  if (!children.length) {
    const text = (element.textContent ?? '').trim();
    return Object.keys(result).length ? { ...result, value: text || null } : (text || null);
  }
  for (const child of children) {
    const key = child.localName || child.nodeName;
    const value = xmlElementToObject(child);
    if (Object.prototype.hasOwnProperty.call(result, key)) {
      result[key] = Array.isArray(result[key]) ? [...result[key], value] : [result[key], value];
    } else result[key] = value;
  }
  const resourceType = element.localName || element.nodeName;
  if (FHIR_RESOURCE_TYPES.has(resourceType)) result.resourceType = resourceType;
  return result;
};

const extractXmlRecords = (text) => {
  if (/<!DOCTYPE|<!ENTITY/i.test(text)) throw new Error('XML DTD and entity declarations are not supported.');
  if (typeof DOMParser === 'undefined') throw new Error('XML parsing is unavailable in this environment.');
  const document = new DOMParser().parseFromString(text, 'application/xml');
  if (document.querySelector('parsererror')) throw new Error('XML is malformed or could not be parsed safely.');
  const root = document.documentElement;
  if (!root) throw new Error('XML document is empty.');
  const resources = Array.from(root.getElementsByTagName('*'))
    .filter((element) => FHIR_RESOURCE_TYPES.has(element.localName || element.nodeName)
      && !Array.from(element.parentElement?.closest?.('*') ? [element.parentElement.closest('*')] : []).some((parent) => FHIR_RESOURCE_TYPES.has(parent.localName || parent.nodeName)));
  if (resources.length) return resources.map(xmlElementToObject);
  const children = Array.from(root.children ?? []);
  const candidates = children.length ? children : [root];
  return candidates.map(xmlElementToObject).map((record) => {
    if (record && typeof record === 'object' && !record.record_type) {
      return { ...record, record_type: first(record.recordType, record.type, record.name, root.localName, 'legacy_xml_record') };
    }
    return record;
  });
};

const parseHl7 = (text, sourceSystem) => {
  const segments = text.split(/[\r\n]+/).map((line) => line.trim()).filter(Boolean);
  if (!segments.some((line) => /^MSH\|/.test(line))) throw new Error('HL7 v2 file must contain an MSH message header.');
  const messages = [];
  let messageSegments = [];
  for (const segment of segments) {
    if (segment.startsWith('MSH|') && messageSegments.length) {
      messages.push(messageSegments);
      messageSegments = [];
    }
    messageSegments.push(segment.split('|'));
  }
  if (messageSegments.length) messages.push(messageSegments);

  const rows = [];
  messages.forEach((message, messageIndex) => {
    const find = (name) => message.find((fields) => fields[0] === name);
    const pid = find('PID');
    const pv1 = find('PV1');
    const msh = find('MSH');
    const patientKey = pid?.[3]?.split('^')[0] || null;
    const encounterKey = pv1?.[19]?.split('^')[0] || null;
    const messageId = msh?.[9] || `message-${messageIndex + 1}`;
    const clinicalSegments = message.filter((fields) => ['PV1', 'OBR', 'OBX', 'DG1', 'AL1', 'RXA', 'RXE', 'PR1', 'TXA', 'NTE', 'ORC'].includes(fields[0]));
    const selected = clinicalSegments.length ? clinicalSegments : [message.find((fields) => fields[0] === 'PID')].filter(Boolean);
    selected.forEach((fields, rowIndex) => {
      const segmentType = fields[0];
      const dateValue = segmentType === 'OBR' ? fields[7]
        : segmentType === 'OBX' ? fields[14]
          : segmentType === 'DG1' ? fields[5]
            : segmentType === 'PV1' ? fields[44]
              : fields[2];
      const displayValue = segmentType === 'OBX' ? fields[5]
        : segmentType === 'OBR' ? fields[4]
          : segmentType === 'DG1' ? fields[3]
            : segmentType === 'AL1' ? fields[3]
              : segmentType === 'NTE' ? fields.slice(3).join('|')
                : fields.slice(2).filter(Boolean).join(' | ');
      const raw = { segment: segmentType, fields, message_control_id: messageId };
      rows.push({
        source_system: sourceSystem,
        source_patient_key: patientKey,
        source_record_id: `${messageId}-${segmentType}-${rowIndex + 1}`,
        record_type: segmentType,
        occurred_at: formatDate(dateValue),
        author_name: null,
        department: null,
        encounter_reference: encounterKey,
        clinical_summary: String(displayValue || segmentType).slice(0, 4000),
        raw_record: raw,
      });
    });
  });
  if (!rows.length) throw new Error('HL7 file contains no supported clinical segments.');
  return rows;
};

/**
 * Parse structured clinical migration files into the existing legacy-record staging shape.
 * This function never writes to the database; callers must use the governed staging workflow.
 */
export const parseClinicalMigrationText = (fileName, text, sourceSystem = 'Legacy system') => {
  if (typeof text !== 'string' || !text.trim()) throw new Error('The selected file is empty.');
  if (new TextEncoder().encode(text).byteLength > MAX_CLINICAL_MIGRATION_TEXT_BYTES) {
    throw new Error('Clinical migration files are limited to 25 MB.');
  }
  const lowerName = String(fileName).toLowerCase();
  let records;
  if (lowerName.endsWith('.json')) {
    let parsed;
    try { parsed = JSON.parse(text); } catch { throw new Error('JSON is malformed. Correct the file and try again.'); }
    records = extractJsonRecords(parsed);
  } else if (lowerName.endsWith('.xml')) {
    records = extractXmlRecords(text);
  } else if (lowerName.endsWith('.hl7') || lowerName.endsWith('.v2') || lowerName.endsWith('.mllp')) {
    return parseHl7(text, sourceSystem);
  } else {
    throw new Error('Choose JSON/FHIR Bundle, XML, or HL7 v2 for legacy clinical records.');
  }
  if (!records.length) throw new Error('The selected file contains no records.');
  if (records.length > 10000) throw new Error('Clinical migration files are limited to 10,000 records.');
  return records.map((record, index) => {
    if (!record || typeof record !== 'object' || Array.isArray(record)) {
      throw new Error(`Record ${index + 1} must be a JSON/XML object.`);
    }
    return toCanonicalRow(record, index, sourceSystem);
  });
};

export const clinicalMigrationSourceFormat = (fileName) => {
  const name = String(fileName).toLowerCase();
  if (name.endsWith('.csv')) return 'csv';
  if (name.endsWith('.xlsx') || name.endsWith('.xls')) return 'xlsx';
  if (name.endsWith('.json')) return 'json';
  if (name.endsWith('.xml')) return 'xml';
  if (name.endsWith('.hl7') || name.endsWith('.v2') || name.endsWith('.mllp')) return 'hl7';
  return 'other';
};
