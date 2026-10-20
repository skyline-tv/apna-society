import { badRequest } from '../../../shared/errors/app-error';

const JPEG = Buffer.from([0xff, 0xd8, 0xff]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const GIF87 = Buffer.from('GIF87a');
const GIF89 = Buffer.from('GIF89a');
const WEBP_RIFF = Buffer.from('RIFF');
const WEBP_WEBP = Buffer.from('WEBP');

export const APPROVED_IMAGE_MIME_TYPES = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
] as const;

export type ApprovedImageMime = (typeof APPROVED_IMAGE_MIME_TYPES)[number];

/**
 * Detect image MIME from magic bytes. Does not trust client Content-Type or filename.
 */
export function detectImageMime(buffer: Buffer): ApprovedImageMime | null {
  if (buffer.length < 12) return null;
  if (buffer.subarray(0, 3).equals(JPEG)) return 'image/jpeg';
  if (buffer.subarray(0, 8).equals(PNG)) return 'image/png';
  if (buffer.subarray(0, 6).equals(GIF87) || buffer.subarray(0, 6).equals(GIF89)) {
    return 'image/gif';
  }
  if (
    buffer.subarray(0, 4).equals(WEBP_RIFF) &&
    buffer.subarray(8, 12).equals(WEBP_WEBP)
  ) {
    return 'image/webp';
  }
  return null;
}

export function assertApprovedImageBuffer(
  buffer: Buffer,
  allowedMimes: readonly string[],
): ApprovedImageMime {
  const detected = detectImageMime(buffer);
  if (!detected || !allowedMimes.includes(detected)) {
    throw badRequest(
      'Attachment must be a valid JPEG, PNG, WebP, or GIF image',
      'INVALID_ATTACHMENT_TYPE',
    );
  }
  return detected;
}
