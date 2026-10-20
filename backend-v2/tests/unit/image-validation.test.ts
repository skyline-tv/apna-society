import { describe, expect, it } from 'vitest';
import {
  assertApprovedImageBuffer,
  detectImageMime,
} from '../../src/modules/complaints/storage/image-validation';
import { AppError } from '../../src/shared/errors/app-error';

describe('image validation', () => {
  it('detects JPEG/PNG/GIF/WebP magic bytes', () => {
    const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(12)]);
    const png = Buffer.concat([
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      Buffer.alloc(8),
    ]);
    const gif = Buffer.concat([Buffer.from('GIF89a'), Buffer.alloc(10)]);
    const webp = Buffer.alloc(16);
    Buffer.from('RIFF').copy(webp, 0);
    Buffer.from('WEBP').copy(webp, 8);

    expect(detectImageMime(jpeg)).toBe('image/jpeg');
    expect(detectImageMime(png)).toBe('image/png');
    expect(detectImageMime(gif)).toBe('image/gif');
    expect(detectImageMime(webp)).toBe('image/webp');
  });

  it('rejects non-image content', () => {
    expect(detectImageMime(Buffer.from('not-an-image!!!!'))).toBeNull();
    expect(() =>
      assertApprovedImageBuffer(Buffer.from('not-an-image!!!!'), ['image/jpeg']),
    ).toThrow(AppError);
  });
});
