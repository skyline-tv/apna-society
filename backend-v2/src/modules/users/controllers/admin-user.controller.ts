import type { Request, Response } from 'express';
import { getRequestSocietyId } from '../../../middleware/admin-society';
import {
  confirmUserMobileVerified,
  deactivateAdminUser,
  getAdminUser,
  listAdminUsers,
  provisionResident,
  setUserMobile,
  updateAdminUser,
} from '../services/admin-user.service';
import type {
  ListUsersQuery,
  ProvisionUserInput,
  SetUserMobileInput,
  UpdateUserInput,
} from '../validators/admin-user.validators';

function actorFrom(req: Request) {
  return {
    userId: req.user!.id,
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? undefined,
  };
}

export async function provisionUserHandler(req: Request, res: Response): Promise<void> {
  const data = await provisionResident(
    getRequestSocietyId(req),
    req.body as ProvisionUserInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function listUsersHandler(req: Request, res: Response): Promise<void> {
  const data = await listAdminUsers(
    getRequestSocietyId(req),
    req.query as unknown as ListUsersQuery,
  );
  res.json({ success: true, data });
}

export async function getUserHandler(req: Request, res: Response): Promise<void> {
  const data = await getAdminUser(getRequestSocietyId(req), String(req.params.userId));
  res.json({ success: true, data });
}

export async function patchUserHandler(req: Request, res: Response): Promise<void> {
  const data = await updateAdminUser(
    getRequestSocietyId(req),
    String(req.params.userId),
    req.body as UpdateUserInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function deactivateUserHandler(req: Request, res: Response): Promise<void> {
  const data = await deactivateAdminUser(
    getRequestSocietyId(req),
    String(req.params.userId),
    actorFrom(req),
    (req.body as { reason?: string }).reason,
  );
  res.json({ success: true, data });
}

export async function setUserMobileHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as SetUserMobileInput;
  const data = await setUserMobile(
    getRequestSocietyId(req),
    String(req.params.userId),
    body.mobile,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function confirmUserMobileHandler(req: Request, res: Response): Promise<void> {
  const data = await confirmUserMobileVerified(
    getRequestSocietyId(req),
    String(req.params.userId),
    actorFrom(req),
  );
  res.json({ success: true, data });
}
