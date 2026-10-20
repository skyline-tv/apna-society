import { badRequest } from '../shared/errors/app-error';

const DEFAULT_REGION = '91';

/**
 * Normalize a mobile number to E.164 without a leading '+'.
 * Default region is India (+91). Accepts 10-digit local, 91XXXXXXXXXX, or +91...
 */
export function normalizeMobileE164(
  raw: string,
  defaultCountryCode = DEFAULT_REGION,
): string {
  const trimmed = raw.trim();
  if (!trimmed) {
    throw badRequest('Mobile number is required', 'INVALID_MOBILE');
  }

  let digits = trimmed.replace(/[^\d+]/g, '');
  if (digits.startsWith('+')) {
    digits = digits.slice(1);
  }
  digits = digits.replace(/\D/g, '');

  if (digits.length === 10 && defaultCountryCode === '91') {
    digits = `${defaultCountryCode}${digits}`;
  }

  // India mobile: 91 + 10 digits starting 6-9
  if (defaultCountryCode === '91') {
    if (!/^91[6-9]\d{9}$/.test(digits)) {
      throw badRequest('Enter a valid Indian mobile number', 'INVALID_MOBILE');
    }
  } else if (digits.length < 10 || digits.length > 15) {
    throw badRequest('Enter a valid mobile number', 'INVALID_MOBILE');
  }

  return digits;
}

/** Display form with + prefix. */
export function formatMobileE164Display(e164Digits: string): string {
  return e164Digits.startsWith('+') ? e164Digits : `+${e164Digits}`;
}
