import type { NextFunction, Request, Response } from 'express';
import { MembershipModel } from '../modules/users/models/membership.model';
import { UserModel } from '../modules/users/models/user.model';
import { forbidden, unauthorized } from '../shared/errors/app-error';
import { isObjectId } from '../utils/object-id';

/**
 * Resolves society context for resident billing APIs.
 * Never trusts societyId from the request body.
 */
export async function resolveResidentSociety(
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
        role: { $in: ['OWNER', 'TENANT', 'ADMIN'] },
      })
        .select('_id')
        .lean();
      if (!membership) {
        next(forbidden('Society access denied', 'SOCIETY_ISOLATION'));
        return;
      }
      societyId = headerSocietyId;
    } else {
      const user = await UserModel.findById(req.user.id).select('primarySocietyId').lean();
      if (user?.primarySocietyId && req.user.societyIds.includes(String(user.primarySocietyId))) {
        societyId = String(user.primarySocietyId);
      } else if (req.user.societyIds[0]) {
        societyId = req.user.societyIds[0];
      }
    }

    if (!societyId) {
      next(forbidden('No society membership found', 'SOCIETY_CONTEXT_REQUIRED'));
      return;
    }

    req.societyId = societyId;
    next();
  } catch (error) {
    next(error);
  }
}
