import { badRequest } from '../../../shared/errors/app-error';
import {
  detectImageMime,
  type ApprovedImageMime,
} from '../../complaints/storage/image-validation';

export type AnnouncementMime = ApprovedImageMime | 'application/pdf';

/**
 * Detect announcement attachment MIME from magic bytes.
 * Does not trust client Content-Type or original filename.
 */
export function detectAnnouncementMime(buffer: Buffer): AnnouncementMime | null {
  if (buffer.length >= 5 && buffer.subarray(0, 5).toString('ascii') === '%PDF-') {
    return 'application/pdf';
  }
  return detectImageMime(buffer);
}

export function assertAnnouncementFileBuffer(
  buffer: Buffer,
  allowedMimes: readonly string[],
): AnnouncementMime {
  const detected = detectAnnouncementMime(buffer);
  if (!detected || !allowedMimes.includes(detected)) {
    throw badRequest(
      'Attachment must be a valid JPEG, PNG, WebP, GIF, or PDF',
      'INVALID_ATTACHMENT_TYPE',
    );
  }
  return detected;
}
