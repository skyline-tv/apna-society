export class AppError extends Error {
  public readonly statusCode: number;
  public readonly code: string;
  public readonly isOperational: boolean;
  public readonly details?: unknown;

  constructor(
    message: string,
    options: {
      statusCode?: number;
      code?: string;
      isOperational?: boolean;
      details?: unknown;
    } = {},
  ) {
    super(message);
    this.name = 'AppError';
    this.statusCode = options.statusCode ?? 500;
    this.code = options.code ?? 'INTERNAL_ERROR';
    this.isOperational = options.isOperational ?? true;
    this.details = options.details;
  }
}

export function badRequest(message: string, code = 'BAD_REQUEST', details?: unknown): AppError {
  return new AppError(message, { statusCode: 400, code, details });
}

export function unauthorized(message = 'Unauthorized', code = 'UNAUTHORIZED'): AppError {
  return new AppError(message, { statusCode: 401, code });
}

export function forbidden(message = 'Forbidden', code = 'FORBIDDEN'): AppError {
  return new AppError(message, { statusCode: 403, code });
}

export function notFound(message = 'Not found', code = 'NOT_FOUND'): AppError {
  return new AppError(message, { statusCode: 404, code });
}

export function conflict(message: string, code = 'CONFLICT'): AppError {
  return new AppError(message, { statusCode: 409, code });
}

export function tooManyRequests(message: string, code = 'RATE_LIMITED'): AppError {
  return new AppError(message, { statusCode: 429, code });
}
