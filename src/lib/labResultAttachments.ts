interface AttachmentRequestError {
  code?: string;
  message?: string;
  status?: number;
}

function errorDetails(error: unknown): AttachmentRequestError {
  if (typeof error === 'object' && error !== null) {
    const candidate = error as { code?: unknown; message?: unknown; status?: unknown };
    return {
      code: typeof candidate.code === 'string' ? candidate.code : undefined,
      message: typeof candidate.message === 'string'
        ? candidate.message
        : error instanceof Error ? error.message : undefined,
      status: typeof candidate.status === 'number' ? candidate.status : undefined,
    };
  }
  if (error instanceof Error) return { message: error.message };
  return {};
}

export function isMissingLabResultAttachmentsTable(error: unknown) {
  const { code, message, status } = errorDetails(error);
  return ((code === 'PGRST205' || code === '42P01') && /lab_result_attachments/i.test(message ?? ''))
    || ((code === 'PGRST202' || code === '404' || status === 404) && /get_lab_result_attachments/i.test(message ?? ''))
    || /could not find the (?:table|function) .*lab_result_(?:attachments|attachements)|relation .*lab_result_attachments.* does not exist|schema cache.*lab_result_(?:attachments|attachements)/i.test(message ?? '');
}

export function isMissingLaboratoryPanelFunction(error: unknown) {
  const { code, message, status } = errorDetails(error);
  return ((code === 'PGRST202' || code === '404' || status === 404) && /get_laboratory_test_groups?/i.test(message ?? ''))
    || /could not find the function .*get_laboratory_test_groups?|function .*get_laboratory_test_groups? .* does not exist|schema cache.*get_laboratory_test_groups?/i.test(message ?? '');
}

export function isMissingInpatientDischargeBillFunction(error: unknown) {
  const { code, message, status } = errorDetails(error);
  return ((code === 'PGRST202' || code === '404' || status === 404) && /get_inpatient_discharge_bill/i.test(message ?? ''))
    || /could not find the function .*get_inpatient_discharge_bill|schema cache.*get_inpatient_discharge_bill/i.test(message ?? '');
}

export const databaseFeatureUpdatingMessage =
  'This feature is currently being updated. Please try again later.';

export function isNetworkFetchError(error: unknown) {
  return error instanceof TypeError
    || (error instanceof Error && /failed to fetch|networkerror|network request failed|load failed/i.test(error.message));
}

export const labResultAttachmentsUnavailableMessage =
  'The deployed database API does not expose laboratory report attachments yet. Apply 20261013180000_laboratory_test_panels.sql, 20261013190000_repair_lab_result_attachments_schema.sql, 20261013200000_laboratory_api_schema_compatibility.sql, and 20261014120000_harden_lab_result_attachment_read_rpc.sql in migration order. Then refresh the PostgREST schema cache and reload the application.';

export const laboratoryPanelsUnavailableMessage =
  'The deployed database API does not expose laboratory panel workflows yet. Apply 20261013180000_laboratory_test_panels.sql and its dependent laboratory API/attachment migrations in order, then refresh the PostgREST schema cache and reload the application.';

export const laboratoryNetworkUnavailableMessage =
  'The laboratory service could not be reached. Check the network connection and Supabase service status, then refresh to retry.';

export const inpatientDischargeBillUnavailableMessage =
  'The deployed database API does not expose the inpatient discharge billing RPC. Apply 20261007083000_reconcile_inpatient_discharge_billing_read_model.sql and 20261014160000_inpatient_discharge_bill_legacy_rpc_compatibility.sql in order, then refresh the PostgREST schema cache and reload the application.';
