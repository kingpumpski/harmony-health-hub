interface AttachmentRequestError {
  code?: string;
  message?: string;
}

export function isMissingLabResultAttachmentsTable(error: AttachmentRequestError) {
  return error.code === 'PGRST205'
    || error.code === '42P01'
    || /could not find the table .*lab_result_attachments|relation .*lab_result_attachments.* does not exist/i.test(error.message ?? '');
}

export const labResultAttachmentsUnavailableMessage =
  'The database attachment table is not available through the API yet. Apply migration 20261013190000_repair_lab_result_attachments_schema.sql and refresh the PostgREST schema cache, then retry.';
