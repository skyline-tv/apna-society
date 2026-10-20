import type { Request, Response } from 'express';
import {
  deactivateResidentVehicle,
  getResidentVehicle,
  listAdminVehicles,
  listResidentVehicles,
  registerVehicle,
  updateResidentVehicle,
} from '../services/vehicle.service';
import type {
  RegisterVehicleInput,
  UpdateVehicleInput,
} from '../validators/vehicle.validators';

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

export async function residentRegisterVehicleHandler(req: Request, res: Response): Promise<void> {
  const data = await registerVehicle(
    societyId(req),
    req.user!.id,
    req.body as RegisterVehicleInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function residentListVehiclesHandler(req: Request, res: Response): Promise<void> {
  const data = await listResidentVehicles(societyId(req), req.user!.id);
  res.json({ success: true, data });
}

export async function residentGetVehicleHandler(req: Request, res: Response): Promise<void> {
  const data = await getResidentVehicle(
    societyId(req),
    req.user!.id,
    String(req.params.vehicleId),
  );
  res.json({ success: true, data });
}

export async function residentUpdateVehicleHandler(req: Request, res: Response): Promise<void> {
  const data = await updateResidentVehicle(
    societyId(req),
    req.user!.id,
    String(req.params.vehicleId),
    req.body as UpdateVehicleInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function residentDeactivateVehicleHandler(req: Request, res: Response): Promise<void> {
  const data = await deactivateResidentVehicle(
    societyId(req),
    req.user!.id,
    String(req.params.vehicleId),
    (req.body as { reason?: string }).reason,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function adminListVehiclesHandler(req: Request, res: Response): Promise<void> {
  const data = await listAdminVehicles(societyId(req), {
    flatId: req.query.flatId as string | undefined,
    isActive: req.query.isActive as boolean | undefined,
    registrationNumber: req.query.registrationNumber as string | undefined,
    page: Number(req.query.page ?? 1),
    limit: Number(req.query.limit ?? 20),
  });
  res.json({ success: true, data });
}
