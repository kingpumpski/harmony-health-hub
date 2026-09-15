# Accessibility, Inclusion and Patient Engagement Specification

## Conformance baseline

WCAG 2.2 AA is the mandatory baseline, with AAA techniques adopted where practical. The implementation also maps to Section 508, EN 301 549 and applicable disability-access requirements.

Accessibility is tested with automated checks, keyboard-only workflows, screen readers, zoom/reflow, contrast, reduced motion, high contrast, large text, touch-target checks and lived-experience testing with disabled users.

## Multi-sensory experience

### Visual
High contrast, dark mode, large text, magnification, non-color status indicators, accessible charts, image descriptions, large-print documents and Braille-display compatibility.

### Hearing
Real-time captions, visual alerts, text-first communication, configurable vibration/haptic alerts and sign-language interpretation integration for supported telehealth workflows.

### Motor and cognitive
Keyboard-only operation, switch/alternative input, voice navigation, guided workflows, simplified patient mode, reduced cognitive load and configurable reading level.

### Voice
Speech-to-text for clinical notes and reports, text-to-speech for results/instructions, configurable language/speed/voice, hands-free navigation and captioning for telehealth.

## Patient engagement model

All patient communications are governed by channel consent, language preference, notification preference, quiet hours, emergency rules and minimum-necessary disclosure.

Channels include in-app, SMS, email, voice, push, WhatsApp where legally/technically approved, and print. The notification service records delivery state without exposing unnecessary PHI in telemetry.

## Messaging

Secure patient-provider messaging supports care-team channels, provider-to-provider consults, templates, priority, escalation, attachments with malware scanning, translation, retention and audit.

## Greetings and sensitive communications

Personalized greetings, birthdays, milestones and culturally appropriate acknowledgements are configurable. Sensitive events such as bereavement require governed templates, suppression rules and authorized staff handling; automation must not create inappropriate or distressing messages.

## Reminders

Appointment, medication, laboratory, imaging, preventive-care, immunization, chronic-care, postoperative, discharge, billing, consent and care-plan reminders use preference-aware escalation. No-response rules are configurable and must never create unsafe clinical assumptions.

## Portal and proxy access

Patients can access appointments, results, medications, messages, bills, insurance, consent and education according to authorization. Caregiver/dependent access uses explicit relationship and scope controls. Pediatric and sensitive-adolescent access requires jurisdiction-specific safeguards.

## Telehealth

Telehealth supports captions, interpretation, virtual waiting room, check-in, asynchronous consultation, remote monitoring, e-prescribing/e-referral where legally supported and AI-assisted pre/post-visit workflows subject to the AI safety model.

## Health literacy

Patient education is personalized by condition, language, reading level and modality. Clinical terminology is translated into understandable patient language without changing the underlying coded concept.

## Feedback and grievances

Patients can submit satisfaction feedback, complaints and grievances through accessible channels. High-risk complaints are escalated according to facility policy and retained as governed service-quality records.

## Accessibility release gate

A release fails if a core clinical or patient workflow cannot be completed using keyboard navigation, a supported screen reader, zoom/reflow, sufficient contrast or the configured alternative communication modality where that modality is part of the workflow.