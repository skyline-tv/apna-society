/**
 * CSV helpers: formula-injection safe cells + streaming-friendly row formatting.
 * Prefixes cells that Excel/Sheets would treat as formulas.
 */

const FORMULA_PREFIX = /^[=+\-@\t\r]/;

export function escapeCsvCell(value: unknown): string {
  let text = value === null || value === undefined ? '' : String(value);
  if (FORMULA_PREFIX.test(text)) {
    text = `'${text}`;
  }
  const needsQuotes = /[",\n\r]/.test(text);
  if (needsQuotes) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

export function csvRow(cells: unknown[]): string {
  return `${cells.map(escapeCsvCell).join(',')}\n`;
}

export function formatIsoDate(value: Date | string | undefined | null): string {
  if (!value) return '';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  return d.toISOString();
}

/** Display currency as rupees with two decimal places from integer paise. */
export function formatPaiseAsRupees(paise: number): string {
  const sign = paise < 0 ? '-' : '';
  const abs = Math.abs(paise);
  const whole = Math.floor(abs / 100);
  const fraction = abs % 100;
  return `${sign}${whole}.${fraction.toString().padStart(2, '0')}`;
}
