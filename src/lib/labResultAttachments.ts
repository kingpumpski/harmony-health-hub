interface AttachmentRequestError {
  code?: string;
  message?: string;
}

export function isMissingLabResultAttachmentsApi(error: AttachmentRequestError) {
  const message = error.message ?? '';
  return error.code === 'PGRST205'
    || error.code === 'PGRST202'
    || error.code === '42P01'
    || /could not find (the table|the function).*lab_result_attachments|relation .*lab_result_attachments.* does not exist|function public\.get_lab_result_attachments.*does not exist/i.test(message);
}

// Backwards-compatible alias used by the clinician report page while both APIs are reconciled.
export const isMissingLabResultAttachmentsTable = isMissingLabResultAttachmentsApi;

export const labResultAttachmentsUnavailableMessage =
  'Laboratory attachment API is not installed or exposed yet. Reconcile and apply migrations 20261013170000_lab_paid_queue_reports_and_catalogue.sql, 20261013180000_laboratory_test_panels.sql, 20261013190000_repair_lab_result_attachments_schema.sql, 20261013200000_lab_result_attachment_read_rpc.sql, 20261013210000_harden_lab_result_approval_facility_boundary.sql, and 20261014110000_diagnostic_workflow_settings_and_context.sql in version order, then reload the PostgREST schema cache and retry.';
