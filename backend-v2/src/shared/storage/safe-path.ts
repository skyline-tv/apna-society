import path from 'path';
import { badRequest } from '../errors/app-error';

/**
 * Resolves a relative opaque storage key under rootDir.
 * Rejects absolute paths, null bytes, backslashes, and path traversal.
 */
export function resolveSafeStoragePath(rootDir: string, storageKey: string): string {
  if (!storageKey || typeof storageKey !== 'string' || storageKey.includes('\0')) {
    throw badRequest('Invalid storage key', 'INVALID_STORAGE_KEY');
  }
  if (path.isAbsolute(storageKey) || storageKey.includes('\\')) {
    throw badRequest('Invalid storage key', 'INVALID_STORAGE_KEY');
  }

  const normalized = path.posix.normalize(storageKey.replace(/^\.\/+/, ''));
  if (
    !normalized ||
    normalized === '.' ||
    normalized.startsWith('../') ||
    normalized.includes('/../') ||
    normalized.split('/').includes('..') ||
    normalized.startsWith('/')
  ) {
    throw badRequest('Invalid storage key', 'INVALID_STORAGE_KEY');
  }

  const root = path.resolve(rootDir);
  const fullPath = path.resolve(root, ...normalized.split('/'));
  const rootPrefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
  if (fullPath !== root && !fullPath.startsWith(rootPrefix)) {
    throw badRequest('Invalid storage key', 'INVALID_STORAGE_KEY');
  }
  return fullPath;
}
