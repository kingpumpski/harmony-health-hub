-- Complete production starter templates for the notification module.
INSERT INTO public.notification_templates(template_key,locale,channel,subject_template,body_template,metadata)
VALUES
('appointment.reminder','en-GH','in_app','Appointment reminder','Your appointment with {{provider_name}} is scheduled for {{date}} at {{time}}.','{"category":"appointments"}'),
('appointment.reminder','en-GH','email','Appointment reminder','Your appointment with {{provider_name}} is scheduled for {{date}} at {{time}}. Location: {{location}}.','{"category":"appointments"}'),
('appointment.reminder','en-GH','sms',NULL,'Appointment reminder: {{provider_name}} on {{date}} at {{time}}.','{"category":"appointments"}'),
('appointment.reminder','en-GH','push','Appointment reminder','{{provider_name}} on {{date}} at {{time}}.','{"category":"appointments"}'),
('appointment.reminder','en-GH','whatsapp',NULL,'Your appointment with {{provider_name}} is scheduled for {{date}} at {{time}}.','{"category":"appointments"}'),
('medication.dose_due','en-GH','in_app','Medication reminder','It is time for your {{medication_name}} dose. Follow your prescribed instructions.','{"category":"medication"}'),
('medication.dose_due','en-GH','email','Medication reminder','It is time for your {{medication_name}} dose. Follow your prescribed instructions.','{"category":"medication"}'),
('medication.dose_due','en-GH','sms',NULL,'Medication reminder: it is time for {{medication_name}}.','{"category":"medication"}'),
('lab.result_available','en-GH','in_app','Laboratory result available','Your laboratory result for {{test_name}} is available for review.','{"category":"clinical"}'),
('lab.result_available','en-GH','email','Laboratory result available','Your laboratory result for {{test_name}} is available in your secure health record.','{"category":"clinical"}'),
('lab.critical_result','en-GH','in_app','Critical laboratory alert','A critical laboratory result requires prompt clinical attention. Please contact your care team or follow the clinical escalation instructions.','{"category":"clinical","critical":true}'),
('lab.critical_result','en-GH','sms',NULL,'Critical laboratory alert: please contact your care team promptly and follow your clinical escalation instructions.','{"category":"clinical","critical":true}'),
('discharge.followup_72h','en-GH','in_app','Post-discharge follow-up','Your post-discharge follow-up is due. Please complete your check-in and contact your care team if you have concerns.','{"category":"clinical"}'),
('discharge.followup_72h','en-GH','email','Post-discharge follow-up','Your post-discharge follow-up is due. Please complete your check-in and contact your care team if you have concerns.','{"category":"clinical"}'),
('review.request','en-GH','in_app','How was your experience?','Please share your experience with {{facility_name}}. Your feedback helps improve care and service.','{"category":"reviews"}'),
('review.request','en-GH','email','How was your experience?','Please share your experience with {{facility_name}}. Your feedback helps improve care and service.','{"category":"reviews"}'),
('greeting.birthday','en-GH','email','Happy birthday','Happy birthday, {{first_name}}. We wish you a healthy and fulfilling year ahead.','{"category":"greetings"}'),
('greeting.birthday','en-GH','in_app','Happy birthday','Happy birthday, {{first_name}}. We wish you a healthy and fulfilling year ahead.','{"category":"greetings"}'),
('greeting.christmas','en-GH','email','Seasonal greetings','Warm seasonal greetings from {{facility_name}}.','{"category":"greetings"}'),
('greeting.world_health_day','en-GH','email','World Health Day','On World Health Day, we encourage you to keep your health and preventive care a priority.','{"category":"wellness"}'),
('wellness.annual_checkup','en-GH','email','Annual health check-up','It may be time for your annual health check-up. Please contact {{facility_name}} to arrange a visit.','{"category":"wellness"}'),
('wellness.annual_checkup','en-GH','in_app','Annual health check-up','It may be time for your annual health check-up. Please contact {{facility_name}} to arrange a visit.','{"category":"wellness"}')
ON CONFLICT(template_key,locale,channel,version) DO UPDATE SET subject_template=EXCLUDED.subject_template,body_template=EXCLUDED.body_template,metadata=EXCLUDED.metadata,active=true,updated_at=now();

-- Ensure the operational core events are enabled at the event-catalog layer.
UPDATE public.notification_events
SET enabled=true, updated_at=now()
WHERE event_name IN (
 'appointment.created','appointment.confirmed','appointment.rescheduled','appointment.cancelled','appointment.reminder',
 'consultation.started','consultation.completed','treatment.started','treatment.completed',
 'lab.order_created','lab.result_available','lab.critical_result',
 'medication.prescribed','medication.dispensed','medication.dose_due','medication.refill_due',
 'discharge.completed','discharge.followup_72h',
 'review.request','wellness.annual_checkup','greeting.birthday','greeting.christmas','greeting.world_health_day',
 'account.welcome','account.password_changed','security.login_alert',
 'billing.invoice_created','billing.payment_received','billing.payment_due',
 'critical.alert','reactivation.reminder'
);
