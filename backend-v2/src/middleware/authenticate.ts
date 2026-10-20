import type { NextFunction, Request, Response } from 'express';
import { unauthorized } from '../shared/errors/app-error';
import { verifyAccessToken } from '../modules/auth/services/token.service';

export function authenticate(req: Request, _res: Response, next: NextFunction): void {
  const header = req.header('authorization');
  if (!header?.startsWith('Bearer ')) {
    next(unauthorized('Authentication required', 'AUTH_REQUIRED'));
    return;
  }

  const token = header.slice('Bearer '.length).trim();
  if (!token) {
    next(unauthorized('Authentication required', 'AUTH_REQUIRED'));
    return;
  }

  try {
    const payload = verifyAccessToken(token);
    req.user = {
      id: payload.sub,
      email: payload.email,
      roles: payload.roles,
      societyIds: payload.societyIds,
    };
    next();
  } catch (error) {
    next(error);
  }
}
