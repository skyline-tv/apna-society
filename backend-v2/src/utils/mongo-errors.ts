import { conflict } from '../shared/errors/app-error';

export function isDuplicateKeyError(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    (error as { code: number }).code === 11000
  );
}

export function isTransientTransactionError(error: unknown): boolean {
  if (typeof error !== 'object' || error === null) {
    return false;
  }
  const err = error as { errorLabels?: string[]; code?: number; codeName?: string };
  return Boolean(
    err.errorLabels?.includes('TransientTransactionError') ||
      err.codeName === 'WriteConflict' ||
      err.code === 112,
  );
}

export function mapMongoWriteError(error: unknown, duplicateMessage: string): never {
  if (isDuplicateKeyError(error)) {
    throw conflict(duplicateMessage, 'DUPLICATE_KEY');
  }
  if (isTransientTransactionError(error)) {
    throw conflict(
      'Concurrent update conflict. Please retry the operation.',
      'TRANSACTION_CONFLICT',
    );
  }
  throw error;
}
