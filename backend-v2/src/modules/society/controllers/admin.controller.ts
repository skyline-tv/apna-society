import type { Request, Response } from 'express';
import { getRequestSocietyId } from '../../../middleware/admin-society';
import { getAdminDashboard } from '../services/admin-dashboard.service';
import {
  createFlat,
  getFlat,
  listFlatResidents,
  listFlats,
  updateFlat,
} from '../services/admin-flat.service';
import {
  getAdminSociety,
  getSocietyConfiguration,
  updateAdminSociety,
} from '../services/admin-society.service';
import { createWing, getWing, listWings, updateWing } from '../services/admin-wing.service';
import {
  assignOwner,
  assignTenant,
  endOwnerOccupancy,
  endTenantOccupancy,
  getOccupancyHistory,
  listOccupancies,
} from '../services/occupancy-lifecycle.service';
import type {
  CreateFlatInput,
  CreateWingInput,
  ListFlatsQuery,
  UpdateFlatInput,
  UpdateSocietyInput,
  UpdateWingInput,
} from '../validators/admin.validators';
import type {
  AssignOccupancyBody,
  EndOccupancyBody,
} from '../validators/occupancy.validators';

function actorFrom(req: Request) {
  return {
    userId: req.user!.id,
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? undefined,
  };
}

export async function getSocietyHandler(req: Request, res: Response): Promise<void> {
  const data = await getAdminSociety(getRequestSocietyId(req));
  res.json({ success: true, data });
}

export async function patchSocietyHandler(req: Request, res: Response): Promise<void> {
  const data = await updateAdminSociety(
    getRequestSocietyId(req),
    req.body as UpdateSocietyInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function getSocietyConfigurationHandler(req: Request, res: Response): Promise<void> {
  const data = await getSocietyConfiguration(getRequestSocietyId(req));
  res.json({ success: true, data });
}

export async function listWingsHandler(req: Request, res: Response): Promise<void> {
  const data = await listWings(getRequestSocietyId(req));
  res.json({ success: true, data });
}

export async function createWingHandler(req: Request, res: Response): Promise<void> {
  const data = await createWing(
    getRequestSocietyId(req),
    req.body as CreateWingInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function getWingHandler(req: Request, res: Response): Promise<void> {
  const data = await getWing(getRequestSocietyId(req), String(req.params.wingId));
  res.json({ success: true, data });
}

export async function patchWingHandler(req: Request, res: Response): Promise<void> {
  const data = await updateWing(
    getRequestSocietyId(req),
    String(req.params.wingId),
    req.body as UpdateWingInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function listFlatsHandler(req: Request, res: Response): Promise<void> {
  const data = await listFlats(getRequestSocietyId(req), req.query as unknown as ListFlatsQuery);
  res.json({ success: true, data });
}

export async function createFlatHandler(req: Request, res: Response): Promise<void> {
  const data = await createFlat(
    getRequestSocietyId(req),
    req.body as CreateFlatInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function getFlatHandler(req: Request, res: Response): Promise<void> {
  const data = await getFlat(getRequestSocietyId(req), String(req.params.flatId));
  res.json({ success: true, data });
}

export async function patchFlatHandler(req: Request, res: Response): Promise<void> {
  const data = await updateFlat(
    getRequestSocietyId(req),
    String(req.params.flatId),
    req.body as UpdateFlatInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function listFlatResidentsHandler(req: Request, res: Response): Promise<void> {
  const data = await listFlatResidents(getRequestSocietyId(req), String(req.params.flatId));
  res.json({ success: true, data });
}

export async function getDashboardHandler(req: Request, res: Response): Promise<void> {
  const data = await getAdminDashboard(getRequestSocietyId(req));
  res.json({ success: true, data });
}

export async function assignOwnerHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as AssignOccupancyBody;
  const data = await assignOwner(
    getRequestSocietyId(req),
    String(req.params.flatId),
    body,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function assignTenantHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as AssignOccupancyBody;
  const data = await assignTenant(
    getRequestSocietyId(req),
    String(req.params.flatId),
    body,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function endOwnerOccupancyHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as EndOccupancyBody;
  const data = await endOwnerOccupancy(
    getRequestSocietyId(req),
    String(req.params.flatId),
    body,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function endTenantOccupancyHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as EndOccupancyBody;
  const data = await endTenantOccupancy(
    getRequestSocietyId(req),
    String(req.params.flatId),
    body,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function occupancyHistoryHandler(req: Request, res: Response): Promise<void> {
  const data = await getOccupancyHistory(
    getRequestSocietyId(req),
    String(req.params.flatId),
    {
      page: Number(req.query.page ?? 1),
      limit: Number(req.query.limit ?? 50),
    },
  );
  res.json({ success: true, data });
}

export async function listOccupanciesHandler(req: Request, res: Response): Promise<void> {
  const data = await listOccupancies(getRequestSocietyId(req), {
    status: req.query.status as 'ACTIVE' | 'ENDED' | undefined,
    role: req.query.role as 'OWNER' | 'TENANT' | undefined,
    flatId: req.query.flatId as string | undefined,
    userId: req.query.userId as string | undefined,
    page: Number(req.query.page ?? 1),
    limit: Number(req.query.limit ?? 20),
  });
  res.json({ success: true, data });
}
