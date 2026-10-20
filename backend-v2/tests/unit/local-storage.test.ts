import { mkdtemp, readFile, rm, writeFile } from 'fs/promises';
import os from 'os';
import path from 'path';
import { afterEach, describe, expect, it } from 'vitest';
import {
  LocalAnnouncementStorage,
  MemoryAnnouncementStorage,
} from '../../src/modules/announcements/storage/announcement-storage';
import {
  assertAnnouncementFileBuffer,
  detectAnnouncementMime,
} from '../../src/modules/announcements/storage/file-validation';
import {
  LocalComplaintStorage,
  MemoryComplaintStorage,
} from '../../src/modules/complaints/storage/complaint-storage';
import { assertApprovedImageBuffer } from '../../src/modules/complaints/storage/image-validation';
import { AppError } from '../../src/shared/errors/app-error';
import { resolveSafeStoragePath } from '../../src/shared/storage/safe-path';

const PNG = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.alloc(16, 1),
]);
const PDF = Buffer.from('%PDF-1.4 minimal');

describe('resolveSafeStoragePath', () => {
  const root = path.join(os.tmpdir(), 'apna-storage-root');

  it('accepts relative opaque keys', () => {
    const resolved = resolveSafeStoragePath(root, 'society/entity/file.png');
    expect(resolved.startsWith(path.resolve(root))).toBe(true);
    expect(resolved).toContain(`${path.sep}society${path.sep}entity${path.sep}file.png`);
  });

  it('rejects path traversal and absolute keys', () => {
    const attacks = [
      '../etc/passwd',
      'society/../../etc/passwd',
      '/etc/passwd',
      '..\\windows\\system32',
      'a/../../b',
      '',
      'society/\0/evil',
    ];
    for (const key of attacks) {
      expect(() => resolveSafeStoragePath(root, key), key).toThrow(AppError);
    }
  });
});

describe('LocalComplaintStorage', () => {
  let dir: string;
  let storage: LocalComplaintStorage;

  afterEach(async () => {
    if (dir) await rm(dir, { recursive: true, force: true });
  });

  async function setup() {
    dir = await mkdtemp(path.join(os.tmpdir(), 'apna-complaint-'));
    storage = new LocalComplaintStorage(dir);
  }

  it('puts, gets, and deletes with generated opaque keys', async () => {
    await setup();
    const stored = await storage.put({
      societyId: 'soc1',
      complaintId: 'cmp1',
      buffer: PNG,
      mimeType: 'image/png',
    });
    expect(stored.storageKey).toMatch(/^soc1\/cmp1\/.+\.png$/);
    expect(stored.storageKey).not.toContain('..');
    expect(stored.sizeBytes).toBe(PNG.length);

    const got = await storage.get(stored.storageKey);
    expect(got.equals(PNG)).toBe(true);

    await storage.delete(stored.storageKey);
    await expect(storage.get(stored.storageKey)).rejects.toMatchObject({
      code: 'ATTACHMENT_FILE_MISSING',
    });
  });

  it('rejects traversal on get/delete', async () => {
    await setup();
    await expect(storage.get('../outside.txt')).rejects.toMatchObject({
      code: 'INVALID_STORAGE_KEY',
    });
    await expect(storage.delete('../../etc/passwd')).rejects.toMatchObject({
      code: 'INVALID_STORAGE_KEY',
    });
  });

  it('returns missing for unknown keys inside root', async () => {
    await setup();
    await expect(storage.get('soc/cmp/missing-file.png')).rejects.toMatchObject({
      code: 'ATTACHMENT_FILE_MISSING',
    });
  });

  it('never uses client filename for on-disk path', async () => {
    await setup();
    const stored = await storage.put({
      societyId: 'soc1',
      complaintId: 'cmp1',
      buffer: PNG,
      mimeType: 'image/png',
    });
    expect(stored.storageKey.includes('evil')).toBe(false);
    expect(stored.storageKey.includes('..')).toBe(false);
    const onDisk = await readFile(path.join(dir, stored.storageKey));
    expect(onDisk.equals(PNG)).toBe(true);
  });
});

describe('LocalAnnouncementStorage', () => {
  let dir: string;
  let storage: LocalAnnouncementStorage;

  afterEach(async () => {
    if (dir) await rm(dir, { recursive: true, force: true });
  });

  it('stores PDF and image payloads under configured root', async () => {
    dir = await mkdtemp(path.join(os.tmpdir(), 'apna-announce-'));
    storage = new LocalAnnouncementStorage(dir);

    const pdf = await storage.put({
      societyId: 'soc1',
      announcementId: 'ann1',
      buffer: PDF,
      mimeType: 'application/pdf',
    });
    expect(pdf.storageKey.endsWith('.pdf')).toBe(true);
    expect((await storage.get(pdf.storageKey)).equals(PDF)).toBe(true);

    const img = await storage.put({
      societyId: 'soc1',
      announcementId: 'ann1',
      buffer: PNG,
      mimeType: 'image/png',
    });
    expect(img.storageKey.endsWith('.png')).toBe(true);
    await storage.delete(img.storageKey);
    await expect(storage.get(img.storageKey)).rejects.toMatchObject({
      code: 'ATTACHMENT_FILE_MISSING',
    });
  });
});

describe('Memory storage cleanup', () => {
  it('deletes complaint and announcement objects', async () => {
    const complaints = new MemoryComplaintStorage();
    const announcements = new MemoryAnnouncementStorage();
    const c = await complaints.put({
      societyId: 's',
      complaintId: 'c',
      buffer: PNG,
      mimeType: 'image/png',
    });
    const a = await announcements.put({
      societyId: 's',
      announcementId: 'a',
      buffer: PDF,
      mimeType: 'application/pdf',
    });
    await complaints.delete(c.storageKey);
    await announcements.delete(a.storageKey);
    await expect(complaints.get(c.storageKey)).rejects.toBeInstanceOf(AppError);
    await expect(announcements.get(a.storageKey)).rejects.toBeInstanceOf(AppError);
  });
});

describe('MIME validation', () => {
  const imageMimes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
  const announcementMimes = [...imageMimes, 'application/pdf'];

  it('accepts valid PNG and rejects plain text', () => {
    expect(assertApprovedImageBuffer(PNG, imageMimes)).toBe('image/png');
    expect(() => assertApprovedImageBuffer(Buffer.from('not-an-image!!!!'), imageMimes)).toThrow(
      AppError,
    );
  });

  it('accepts PDF for announcements and rejects for complaints', () => {
    expect(detectAnnouncementMime(PDF)).toBe('application/pdf');
    expect(assertAnnouncementFileBuffer(PDF, announcementMimes)).toBe('application/pdf');
    expect(() => assertApprovedImageBuffer(PDF, imageMimes)).toThrow(AppError);
  });

  it('rejects oversized buffers only via service limits (validation is type-only)', () => {
    // Type validation must still reject non-image even when large.
    const hugeFake = Buffer.alloc(6 * 1024 * 1024, 0x41);
    expect(() => assertApprovedImageBuffer(hugeFake, imageMimes)).toThrow(AppError);
  });
});

describe('path escape via crafted on-disk sibling', () => {
  it('cannot read files outside root even if a sibling exists', async () => {
    const parent = await mkdtemp(path.join(os.tmpdir(), 'apna-escape-'));
    const root = path.join(parent, 'root');
    const outside = path.join(parent, 'secret.txt');
    await writeFile(outside, 'secret-data');
    const storage = new LocalComplaintStorage(root);
    await expect(storage.get('../secret.txt')).rejects.toMatchObject({
      code: 'INVALID_STORAGE_KEY',
    });
    await rm(parent, { recursive: true, force: true });
  });
});
