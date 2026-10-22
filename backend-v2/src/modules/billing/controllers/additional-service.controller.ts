import type { Request, Response } from 'express';
import { getRequestSocietyId } from '../../../middleware/admin-society';
import {
  createAdditionalService,
  deactivateAdditionalService,
  getAdditionalService,
  listAdditionalServices,
  updateAdditionalService,
} from '../services/additional-service.service';
import type {
  CreateAdditionalServiceInput,
  DeactivateAdditionalServiceInput,
  ListAdditionalServicesQuery,
  UpdateAdditionalServiceInput,
} from '../validators/additional-service.validators';

function actorFrom(req: Request) {
  return {
    userId: req.user!.id,
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? undefined,
  };
}

export async function createAdditionalServiceHandler(req: Request, res: Response): Promise<void> {
  const data = await createAdditionalService(
    getRequestSocietyId(req),
    req.body as CreateAdditionalServiceInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function listAdditionalServicesHandler(req: Request, res: Response): Promise<void> {
  const data = await listAdditionalServices(
    getRequestSocietyId(req),
    req.query as unknown as ListAdditionalServicesQuery,
  );
  res.json({ success: true, data });
}

export async function getAdditionalServiceHandler(req: Request, res: Response): Promise<void> {
  const data = await getAdditionalService(
    getRequestSocietyId(req),
    String(req.params.serviceId),
  );
  res.json({ success: true, data });
}

export async function updateAdditionalServiceHandler(req: Request, res: Response): Promise<void> {
  const data = await updateAdditionalService(
    getRequestSocietyId(req),
    String(req.params.serviceId),
    req.body as UpdateAdditionalServiceInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function deactivateAdditionalServiceHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await deactivateAdditionalService(
    getRequestSocietyId(req),
    String(req.params.serviceId),
    req.body as DeactivateAdditionalServiceInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}
