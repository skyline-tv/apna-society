import type { NextFunction, Request, Response } from 'express';
import type { Role } from '../config/constants';
import { isResidentPushRole } from '../modules/notifications/services/fcm-access';
import { forbidden, unauthorized } from '../shared/errors/app-error';

/**
 * Role gate only. Flat-level authorization must still be enforced in services
 * using Membership + societyId + flatId checks.
 */
export function requireRoles(...allowed: Role[]) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    if (!req.user) {
      next(unauthorized('Authentication required', 'AUTH_REQUIRED'));
      return;
    }
    const hasRole = req.user.roles.some((role) => allowed.includes(role));
    if (!hasRole) {
      next(forbidden('Insufficient role', 'FORBIDDEN_ROLE'));
      return;
    }
    next();
  };
}

/** Device-token routes: owners and tenants only. Admins and guards are rejected. */
export function requireResidentPushAccess(
  req: Request,
  _res: Response,
  next: NextFunction,
): void {
  if (!req.user) {
    next(unauthorized('Authentication required', 'AUTH_REQUIRED'));
    return;
  }
  if (!isResidentPushRole(req.user.roles)) {
    next(
      forbidden(
        'Only resident owners and tenants can register for push notifications',
        'FCM_RESIDENT_ONLY',
      ),
    );
    return;
  }
  next();
}

export function requireSocietyAccess(paramName = 'societyId') {
  return (req: Request, _res: Response, next: NextFunction): void => {
    if (!req.user) {
      next(unauthorized('Authentication required', 'AUTH_REQUIRED'));
      return;
    }
    if (req.user.roles.includes('ADMIN')) {
      next();
      return;
    }
    const societyId = String(req.params[paramName] ?? req.header('x-society-id') ?? '');
    if (!societyId || !req.user.societyIds.includes(societyId)) {
      next(forbidden('Society access denied', 'SOCIETY_ISOLATION'));
      return;
    }
    req.societyId = societyId;
    next();
  };
}
