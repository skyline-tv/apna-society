import type { Request, Response } from 'express';
import { getRequestSocietyId } from '../../../middleware/admin-society';
import {
  deactivateGuard,
  getGuard,
  listGuards,
  provisionGuard,
  updateGuard,
} from '../../users/services/admin-guard.service';
import type {
  ProvisionGuardInput,
  UpdateGuardInput,
} from '../validators/visitor.validators';

function actorFrom(req: Request) {
  return {
    userId: req.user!.id,
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? undefined,
  };
}

export async function provisionGuardHandler(req: Request, res: Response): Promise<void> {
  const data = await provisionGuard(
    getRequestSocietyId(req),
    req.body as ProvisionGuardInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function listGuardsHandler(req: Request, res: Response): Promise<void> {
  const data = await listGuards(getRequestSocietyId(req), req.query as never);
  res.json({ success: true, data });
}

export async function getGuardHandler(req: Request, res: Response): Promise<void> {
  const data = await getGuard(getRequestSocietyId(req), String(req.params.guardId));
  res.json({ success: true, data });
}

export async function patchGuardHandler(req: Request, res: Response): Promise<void> {
  const data = await updateGuard(
    getRequestSocietyId(req),
    String(req.params.guardId),
    req.body as UpdateGuardInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function deactivateGuardHandler(req: Request, res: Response): Promise<void> {
  const data = await deactivateGuard(
    getRequestSocietyId(req),
    String(req.params.guardId),
    (req.body as { reason?: string }).reason,
    actorFrom(req),
  );
  res.json({ success: true, data });
}
