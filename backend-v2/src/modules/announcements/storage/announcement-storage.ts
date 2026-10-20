import { createHash, randomUUID } from 'crypto';
import { mkdir, readFile, unlink, writeFile } from 'fs/promises';
import path from 'path';
import { getEnv } from '../../../config/env';
import { notFound } from '../../../shared/errors/app-error';
import { resolveSafeStoragePath } from '../../../shared/storage/safe-path';
import { S3ObjectStorage } from '../../../shared/storage/s3-object-storage';

export interface StoredObject {
  storageKey: string;
  sizeBytes: number;
}

export interface AnnouncementStorageAdapter {
  put(input: {
    societyId: string;
    announcementId: string;
    buffer: Buffer;
    mimeType: string;
  }): Promise<StoredObject>;
  get(storageKey: string): Promise<Buffer>;
  delete(storageKey: string): Promise<void>;
}

function extensionForMime(mimeType: string): string {
  if (mimeType === 'application/pdf') return 'pdf';
  if (mimeType === 'image/png') return 'png';
  if (mimeType === 'image/webp') return 'webp';
  if (mimeType === 'image/gif') return 'gif';
  return 'jpg';
}

/**
 * Local filesystem adapter for announcement attachments.
 * Keys are opaque relative paths under the configured directory — never returned to clients.
 */
export class LocalAnnouncementStorage implements AnnouncementStorageAdapter {
  constructor(private readonly rootDir: string) {}

  async put(input: {
    societyId: string;
    announcementId: string;
    buffer: Buffer;
    mimeType: string;
  }): Promise<StoredObject> {
    const ext = extensionForMime(input.mimeType);
    const hash = createHash('sha256').update(input.buffer).digest('hex').slice(0, 16);
    const storageKey = path.posix.join(
      input.societyId,
      input.announcementId,
      `${randomUUID()}-${hash}.${ext}`,
    );
    const fullPath = resolveSafeStoragePath(this.rootDir, storageKey);
    await mkdir(path.dirname(fullPath), { recursive: true });
    await writeFile(fullPath, input.buffer, { flag: 'wx' });
    return { storageKey, sizeBytes: input.buffer.length };
  }

  async get(storageKey: string): Promise<Buffer> {
    const fullPath = resolveSafeStoragePath(this.rootDir, storageKey);
    try {
      return await readFile(fullPath);
    } catch {
      throw notFound('Attachment file not found', 'ATTACHMENT_FILE_MISSING');
    }
  }

  async delete(storageKey: string): Promise<void> {
    const fullPath = resolveSafeStoragePath(this.rootDir, storageKey);
    try {
      await unlink(fullPath);
    } catch {
      // Missing file on cleanup is non-fatal.
    }
  }
}

export class MemoryAnnouncementStorage implements AnnouncementStorageAdapter {
  private readonly files = new Map<string, Buffer>();

  async put(input: {
    societyId: string;
    announcementId: string;
    buffer: Buffer;
    mimeType: string;
  }): Promise<StoredObject> {
    const storageKey = `${input.societyId}/${input.announcementId}/${randomUUID()}`;
    this.files.set(storageKey, Buffer.from(input.buffer));
    return { storageKey, sizeBytes: input.buffer.length };
  }

  async get(storageKey: string): Promise<Buffer> {
    const buf = this.files.get(storageKey);
    if (!buf) throw notFound('Attachment file not found', 'ATTACHMENT_FILE_MISSING');
    return buf;
  }

  async delete(storageKey: string): Promise<void> {
    this.files.delete(storageKey);
  }

  clear(): void {
    this.files.clear();
  }
}

let override: AnnouncementStorageAdapter | null = null;
let memorySingleton: MemoryAnnouncementStorage | null = null;

export function setAnnouncementStorageForTests(adapter: AnnouncementStorageAdapter | null): void {
  override = adapter;
}

export function getMemoryAnnouncementStorage(): MemoryAnnouncementStorage {
  if (!memorySingleton) memorySingleton = new MemoryAnnouncementStorage();
  return memorySingleton;
}

export function getAnnouncementStorage(): AnnouncementStorageAdapter {
  if (override) return override;
  const env = getEnv();
  if (env.ANNOUNCEMENT_STORAGE_PROVIDER === 'memory') {
    return getMemoryAnnouncementStorage();
  }
  if (env.ANNOUNCEMENT_STORAGE_PROVIDER === 's3') {
    const s3 = new S3ObjectStorage();
    return {
      put: (input) =>
        s3.put({
          namespace: 'announcements',
          societyId: input.societyId,
          entityId: input.announcementId,
          buffer: input.buffer,
          mimeType: input.mimeType,
        }),
      get: (key) => s3.get(key),
      delete: (key) => s3.delete(key),
    };
  }
  return new LocalAnnouncementStorage(env.ANNOUNCEMENT_STORAGE_LOCAL_DIR);
}
