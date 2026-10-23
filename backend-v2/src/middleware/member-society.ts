import type { NextFunction, Request, Response } from 'express';
import { MembershipModel } from '../modules/users/models/membership.model';
import { UserModel } from '../modules/users/models/user.model';
import { forbidden, unauthorized } from '../shared/errors/app-error';
import { isObjectId } from '../utils/object-id';

/**
 * Resolves society context for any authenticated member (owner, tenant, admin, guard).
 * Never trusts societyId from the request body.
 */
export async function resolveMemberSociety(
  req: Request,
  _res: Response,
  next: NextFunction,
): Promise<void> {
  try {
    if (!req.user) {
      next(unauthorized('Authentication required', 'AUTH_REQUIRED'));
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
        isActive: true,
      })
        .select('_id')
        .lean();
      if (!membership) {
        next(forbidden('Society access denied', 'SOCIETY_ISOLATION'));
        return;
      }
      societyId = headerSocietyId;
    } else {
      const user = await UserModel.findById(req.user.id).select('primarySocietyId isActive').lean();
      if (!user?.isActive) {
        next(forbidden('Account is inactive', 'ACCOUNT_INACTIVE'));
        return;
      }
      if (user.primarySocietyId) {
        const membership = await MembershipModel.findOne({
          userId: req.user.id,
          societyId: user.primarySocietyId,
          isActive: true,
        })
          .select('_id')
          .lean();
        if (membership) societyId = String(user.primarySocietyId);
      }
      if (!societyId) {
        const membership = await MembershipModel.findOne({
          userId: req.user.id,
          isActive: true,
        })
          .sort({ createdAt: 1 })
          .select('societyId')
          .lean();
        if (membership) societyId = String(membership.societyId);
      }
    }

    if (!societyId) {
      next(forbidden('No active society membership found', 'SOCIETY_CONTEXT_REQUIRED'));
      return;
    }

    req.societyId = societyId;
    next();
  } catch (error) {
    next(error);
  }
}
