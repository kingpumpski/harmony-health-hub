/** Format a Date for a datetime-local input in the user's local timezone.
 * datetime-local values contain no timezone; using toISOString() directly shifts
 * the displayed clock time to UTC and can schedule visits at the wrong local time.
 */
export function toLocalDateTimeInputValue(date: Date = new Date()): string {
  const localMilliseconds = date.getTime() - date.getTimezoneOffset() * 60_000;
  return new Date(localMilliseconds).toISOString().slice(0, 16);
}
