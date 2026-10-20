import type { NextFunction, Request, Response } from 'express';
import { MembershipModel } from '../modules/users/models/membership.model';
import { UserModel } from '../modules/users/models/user.model';
import { forbidden, unauthorized } from '../shared/errors/app-error';
import { isObjectId } from '../utils/object-id';

/**
 * Resolves the admin's society context from authenticated membership.
 * Never trusts societyId from the request body.
 * Optional `x-society-id` header is accepted only when the admin belongs to that society.
 */
export async function resolveAdminSociety(
  req: Request,
  _res: Response,
  next: NextFunction,
): Promise<void> {
  try {
    if (!req.user) {
      next(unauthorized('Authentication required', 'AUTH_REQUIRED'));
      return;
    }

    if (!req.user.roles.includes('ADMIN')) {
      next(forbidden('Admin role required', 'FORBIDDEN_ROLE'));
      return;
    }

    const headerSocietyId = req.header('x-society-id')?.trim();
    let societyId: string | undefined;

    if (headerSocietyId) {
      if (!isObjectId(headerSocietyId)) {
        next(forbidden('Invalid society context', 'INVALID_SOCIETY_CONTEXT'));
        return;
      }
      const membership = await MembershipModel.findOne({
        userId: req.user.id,
        societyId: headerSocietyId,
        role: 'ADMIN',
        isActive: true,
      })
        .select('_id')
        .lean();
      if (!membership && !req.user.societyIds.includes(headerSocietyId)) {
        next(forbidden('Society access denied', 'SOCIETY_ISOLATION'));
        return;
      }
      // Require an active ADMIN membership for the requested society.
      if (!membership) {
        next(forbidden('Society access denied', 'SOCIETY_ISOLATION'));
        return;
      }
      societyId = headerSocietyId;
    } else {
      const user = await UserModel.findById(req.user.id).select('primarySocietyId').lean();
      if (user?.primarySocietyId) {
        const membership = await MembershipModel.findOne({
          userId: req.user.id,
          societyId: user.primarySocietyId,
          role: 'ADMIN',
          isActive: true,
        })
          .select('_id')
          .lean();
        if (membership) {
          societyId = String(user.primarySocietyId);
        }
      }

      if (!societyId) {
        const membership = await MembershipModel.findOne({
          userId: req.user.id,
          role: 'ADMIN',
          isActive: true,
        })
          .sort({ createdAt: 1 })
          .select('societyId')
          .lean();
        if (membership) {
          societyId = String(membership.societyId);
        }
      }
    }

    if (!societyId) {
      next(forbidden('No admin society membership found', 'SOCIETY_CONTEXT_REQUIRED'));
      return;
    }

    req.societyId = societyId;
    next();
  } catch (error) {
    next(error);
  }
}

export function getRequestSocietyId(req: Request): string {
  return String(req.societyId);
}
