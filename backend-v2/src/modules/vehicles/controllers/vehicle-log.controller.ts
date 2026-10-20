import type { Request, Response } from 'express';
import {
  listVehicleLogs,
  recordVehicleEntry,
  recordVehicleExit,
} from '../services/vehicle-log.service';
import type { VehicleEntryInput, VehicleExitInput } from '../validators/vehicle.validators';

function actorFrom(req: Request) {
  return {
    userId: req.user!.id,
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? undefined,
  };
}

function societyId(req: Request): string {
  return String(req.societyId);
}

export async function guardVehicleEntryHandler(req: Request, res: Response): Promise<void> {
  const data = await recordVehicleEntry(
    societyId(req),
    req.user!.id,
    req.body as VehicleEntryInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function guardVehicleExitHandler(req: Request, res: Response): Promise<void> {
  const data = await recordVehicleExit(
    societyId(req),
    req.user!.id,
    req.body as VehicleExitInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function guardListVehicleLogsHandler(req: Request, res: Response): Promise<void> {
  const data = await listVehicleLogs(societyId(req), {
    status: req.query.status as string | undefined,
    registrationNumber: req.query.registrationNumber as string | undefined,
    vehicleId: req.query.vehicleId as string | undefined,
    from: req.query.from ? new Date(String(req.query.from)) : undefined,
    to: req.query.to ? new Date(String(req.query.to)) : undefined,
    page: Number(req.query.page ?? 1),
    limit: Number(req.query.limit ?? 20),
  });
  res.json({ success: true, data });
}
