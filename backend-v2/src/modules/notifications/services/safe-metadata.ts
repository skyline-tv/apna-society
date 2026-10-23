const SECRET_KEY = /otp|password|token|secret|jwt|authorization|refresh|credential/i;

const ALLOWED_KEYS = new Set([
  'flatLabel',
  'flatNumber',
  'visitorName',
  'visitorPhone',
  'visitorType',
  'purpose',
  'entryAt',
  'entryMode',
  'guardName',
  'requestId',
  'requestTime',
  'expiresAt',
  'billingMonth',
  'originalAmountPaise',
  'outstandingAmountPaise',
  'outstandingPrincipalPaise',
  'accruedInterestPaise',
  'totalPayablePaise',
  'dueDate',
  'channel',
  'priority',
  'callAction',
  'deepLink',
  'parcelStatus',
  'parcelId',
  'dueStatus',
]);

function isPlainValue(value: unknown): boolean {
  return (
    value === null ||
    typeof value === 'string' ||
    typeof value === 'number' ||
    typeof value === 'boolean'
  );
}

/** Drop secrets and unknown keys before persisting or returning metadata. */
export function sanitizeNotificationMetadata(
  input?: Record<string, unknown>,
): Record<string, unknown> | undefined {
  if (!input) return undefined;
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (SECRET_KEY.test(key)) continue;
    if (!ALLOWED_KEYS.has(key)) continue;
    if (!isPlainValue(value)) continue;
    if (typeof value === 'string' && value.length > 500) {
      out[key] = value.slice(0, 500);
    } else {
      out[key] = value;
    }
  }
  return Object.keys(out).length ? out : undefined;
}

/** FCM data payloads must be string-to-string. */
export function metadataToFcmData(
  metadata?: Record<string, unknown>,
): Record<string, string> {
  const safe = sanitizeNotificationMetadata(metadata) ?? {};
  const data: Record<string, string> = {};
  for (const [key, value] of Object.entries(safe)) {
    if (value === null || value === undefined) continue;
    data[key] = String(value);
  }
  return data;
}
