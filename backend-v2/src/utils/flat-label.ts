/**
 * Compose `WING-NUMBER` from structured fields.
 *
 * Flat `number` is often stored as `E-303` already. Callers must not
 * concatenate wing + number blindly or the label becomes `E-E-303`.
 * Stored records are left unchanged; this is display/serialization only.
 */
export function formatFlatLabel(
  wingCode?: string | null,
  flatNumber?: string | null,
): string {
  const wing = (wingCode ?? '').trim().toUpperCase();
  let number = (flatNumber ?? '').trim().toUpperCase();
  if (!number && !wing) return '';
  if (!wing) return number;

  const prefix = `${wing}-`;
  while (number.startsWith(prefix)) {
    number = number.slice(prefix.length);
  }
  if (number.startsWith(wing) && number.length > wing.length && /^\d/.test(number.slice(wing.length))) {
    number = number.slice(wing.length).replace(/^-+/, '');
  }
  if (!number || number === wing) return wing;
  return `${wing}-${number}`;
}
