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

export interface ComplaintStorageAdapter {
  put(input: {
    societyId: string;
    complaintId: string;
    buffer: Buffer;
    mimeType: string;
  }): Promise<StoredObject>;
  get(storageKey: string): Promise<Buffer>;
  delete(storageKey: string): Promise<void>;
}

function extensionForMime(mimeType: string): string {
  if (mimeType === 'image/png') return 'png';
  if (mimeType === 'image/webp') return 'webp';
  if (mimeType === 'image/gif') return 'gif';
  return 'jpg';
}

/**
 * Local filesystem adapter.
 * Keys are opaque relative paths under the configured directory — never returned to clients.
 */
export class LocalComplaintStorage implements ComplaintStorageAdapter {
  constructor(private readonly rootDir: string) {}

  async put(input: {
    societyId: string;
    complaintId: string;
    buffer: Buffer;
    mimeType: string;
  }): Promise<StoredObject> {
    const ext = extensionForMime(input.mimeType);
    const hash = createHash('sha256').update(input.buffer).digest('hex').slice(0, 16);
    const storageKey = path.posix.join(
      input.societyId,
      input.complaintId,
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

/** In-memory adapter for unit/integration tests without touching disk. */
export class MemoryComplaintStorage implements ComplaintStorageAdapter {
  private readonly files = new Map<string, Buffer>();

  async put(input: {
    societyId: string;
    complaintId: string;
    buffer: Buffer;
    mimeType: string;
  }): Promise<StoredObject> {
    const storageKey = `${input.societyId}/${input.complaintId}/${randomUUID()}`;
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

let overrideAdapter: ComplaintStorageAdapter | null = null;
let memorySingleton: MemoryComplaintStorage | null = null;

export function setComplaintStorageForTests(adapter: ComplaintStorageAdapter | null): void {
  overrideAdapter = adapter;
}

export function getMemoryComplaintStorage(): MemoryComplaintStorage {
  if (!memorySingleton) memorySingleton = new MemoryComplaintStorage();
  return memorySingleton;
}

export function getComplaintStorage(): ComplaintStorageAdapter {
  if (overrideAdapter) return overrideAdapter;
  const env = getEnv();
  if (env.COMPLAINT_STORAGE_PROVIDER === 'memory') {
    return getMemoryComplaintStorage();
  }
  if (env.COMPLAINT_STORAGE_PROVIDER === 's3') {
    const s3 = new S3ObjectStorage();
    return {
      put: (input) =>
        s3.put({
          namespace: 'complaints',
          societyId: input.societyId,
          entityId: input.complaintId,
          buffer: input.buffer,
          mimeType: input.mimeType,
        }),
      get: (key) => s3.get(key),
      delete: (key) => s3.delete(key),
    };
  }
  return new LocalComplaintStorage(env.COMPLAINT_STORAGE_LOCAL_DIR);
}
