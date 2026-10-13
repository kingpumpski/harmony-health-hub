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
  'Laboratory attachment schema is not installed or exposed yet. Reconcile and apply migrations 20261013170000_lab_paid_queue_reports_and_catalogue.sql, 20261013180000_laboratory_test_panels.sql, and 20261013190000_repair_lab_result_attachments_schema.sql in version order, then reload the PostgREST schema cache and retry. Do not apply the later migrations out of order.';
