# RecordList API

The shared RecordList<T> component is intended for standard record-bearing collections, not specialized clinical workflow boards.

## Core props
- title: page/list title.
- description: optional operational context.
- data: current record collection.
- columns: RecordColumn<T>[].
- isLoading: skeleton state.
- error: list-level error.
- rowKey: stable row identifier.
- onRowClick: optional keyboard/mouse row navigation.
- onAddNew: optional authorized create action.
- onRefresh: optional refresh action.
- searchSlot / filterSlot: optional controls.
- emptyState: empty-state content.
- pagination props: page, pageSize, total, onPageChange.

## Column configuration
RecordColumn<T> supports key, header, width, align, sortable metadata, hideBelow and render(row, index).

## Status presentation
Use the exported StatusBadge for common statuses. Domain-specific clinical severity indicators may continue using their existing clinical components where they communicate more than a generic status.

## Architectural rules
1. Do not use RecordList for Emergency, Theatre, Transfusion, Nursing Handover, Medication Administration, Inpatient workflow or other specialized boards merely for visual consistency.
2. Create/update/delete must continue through existing authorized domain mutations.
3. Query invalidation belongs to the domain query owner.
4. Never use RecordList to bypass RLS, permissions or module governance.
5. Do not expose patient information that the underlying query did not authorize.
6. Reuse PatientAvatar for patient identity where appropriate.