import {
  DeleteObjectCommand,
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { createHash, randomUUID } from 'crypto';
import { getEnv } from '../../config/env';
import { badRequest, notFound } from '../errors/app-error';

export interface ObjectStored {
  storageKey: string;
  sizeBytes: number;
}

function createS3Client(): S3Client {
  const env = getEnv();
  return new S3Client({
    region: env.S3_REGION || 'auto',
    endpoint: env.S3_ENDPOINT || undefined,
    forcePathStyle: env.S3_FORCE_PATH_STYLE,
    credentials: {
      accessKeyId: env.S3_ACCESS_KEY_ID,
      secretAccessKey: env.S3_SECRET_ACCESS_KEY,
    },
  });
}

function extensionForMime(mimeType: string): string {
  if (mimeType === 'application/pdf') return 'pdf';
  if (mimeType === 'image/png') return 'png';
  if (mimeType === 'image/webp') return 'webp';
  if (mimeType === 'image/gif') return 'gif';
  return 'jpg';
}

/**
 * S3-compatible object storage (AWS S3, MinIO, Cloudflare R2, etc.).
 */
export class S3ObjectStorage {
  private readonly client = createS3Client();
  private readonly bucket = getEnv().S3_BUCKET;
  private readonly prefix = getEnv().S3_KEY_PREFIX.replace(/^\/+|\/+$/g, '');

  async put(input: {
    namespace: string;
    societyId: string;
    entityId: string;
    buffer: Buffer;
    mimeType: string;
  }): Promise<ObjectStored> {
    const ext = extensionForMime(input.mimeType);
    const hash = createHash('sha256').update(input.buffer).digest('hex').slice(0, 16);
    const storageKey = [
      this.prefix,
      input.namespace,
      input.societyId,
      input.entityId,
      `${randomUUID()}-${hash}.${ext}`,
    ]
      .filter(Boolean)
      .join('/');

    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: storageKey,
        Body: input.buffer,
        ContentType: input.mimeType,
      }),
    );
    return { storageKey, sizeBytes: input.buffer.length };
  }

  async get(storageKey: string): Promise<Buffer> {
    if (!storageKey || storageKey.includes('..') || storageKey.includes('\\')) {
      throw badRequest('Invalid storage key', 'INVALID_STORAGE_KEY');
    }
    try {
      const result = await this.client.send(
        new GetObjectCommand({ Bucket: this.bucket, Key: storageKey }),
      );
      const bytes = await result.Body?.transformToByteArray();
      if (!bytes) throw notFound('Attachment file not found', 'ATTACHMENT_FILE_MISSING');
      return Buffer.from(bytes);
    } catch (error) {
      if ((error as { name?: string }).name === 'NoSuchKey') {
        throw notFound('Attachment file not found', 'ATTACHMENT_FILE_MISSING');
      }
      throw error;
    }
  }

  async delete(storageKey: string): Promise<void> {
    if (!storageKey || storageKey.includes('..') || storageKey.includes('\\')) {
      throw badRequest('Invalid storage key', 'INVALID_STORAGE_KEY');
    }
    try {
      await this.client.send(
        new DeleteObjectCommand({ Bucket: this.bucket, Key: storageKey }),
      );
    } catch {
      // Missing object on cleanup is non-fatal.
    }
  }
}
