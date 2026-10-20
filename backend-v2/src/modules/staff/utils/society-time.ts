import {
  civilDateInTimeZone,
  type CivilDate,
} from '../../billing/utils/billing-calendar';

export function formatCivilDate(civil: CivilDate): string {
  return `${civil.year}-${String(civil.month).padStart(2, '0')}-${String(civil.day).padStart(2, '0')}`;
}

export function localDateString(date: Date, timeZone: string): string {
  return formatCivilDate(civilDateInTimeZone(date, timeZone));
}

/**
 * Combine YYYY-MM-DD + HH:mm into an absolute Instant.
 * Uses fixed +05:30 for Asia/Kolkata (no DST). Other zones fall back to ISO with offset lookup via Intl.
 */
export function zonedDateTime(localDate: string, hhmm: string, timeZone: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(localDate)) {
    throw new Error('Invalid local date');
  }
  if (!/^\d{2}:\d{2}$/.test(hhmm)) {
    throw new Error('Invalid time');
  }
  if (timeZone === 'Asia/Kolkata' || timeZone === 'Asia/Calcutta') {
    return new Date(`${localDate}T${hhmm}:00.000+05:30`);
  }

  // Approximate: construct as UTC then adjust using formatter offset for that zone.
  const probe = new Date(`${localDate}T${hhmm}:00.000Z`);
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone,
    timeZoneName: 'shortOffset',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  });
  const parts = fmt.formatToParts(probe);
  const tzName = parts.find((p) => p.type === 'timeZoneName')?.value ?? 'GMT';
  const match = tzName.match(/GMT([+-]\d{1,2})(?::?(\d{2}))?/i);
  let offset = '+00:00';
  if (match) {
    const h = Number(match[1]);
    const m = match[2] ? Number(match[2]) : 0;
    const sign = h < 0 || String(match[1]).startsWith('-') ? '-' : '+';
    offset = `${sign}${String(Math.abs(h)).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
  }
  return new Date(`${localDate}T${hhmm}:00.000${offset}`);
}

export function parseHhMm(value: string): { hours: number; minutes: number } {
  const [h, m] = value.split(':').map(Number);
  return { hours: h, minutes: m };
}

export function minutesBetween(startHhmm: string, endHhmm: string, overnight: boolean): number {
  const a = parseHhMm(startHhmm);
  const b = parseHhMm(endHhmm);
  const start = a.hours * 60 + a.minutes;
  let end = b.hours * 60 + b.minutes;
  if (overnight || end <= start) end += 24 * 60;
  return end - start;
}

export function rangesOverlap(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date): boolean {
  return aStart.getTime() < bEnd.getTime() && bStart.getTime() < aEnd.getTime();
}

export function normalizePhone(raw: string): string {
  return raw.trim().replace(/[\s()-]/g, '');
}

export function addCivilDays(localDate: string, days: number): string {
  const [y, m, d] = localDate.split('-').map(Number);
  const utc = new Date(Date.UTC(y, m - 1, d + days));
  return `${utc.getUTCFullYear()}-${String(utc.getUTCMonth() + 1).padStart(2, '0')}-${String(utc.getUTCDate()).padStart(2, '0')}`;
}
