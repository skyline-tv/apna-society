import type { Request, Response } from 'express';
import {
  adminDeactivateVehicle,
  adminRegisterVehicle,
  adminUpdateVehicle,
  assertResidentVehicleReadOnly,
  getResidentVehicle,
  listAdminVehicles,
  listResidentVehicles,
} from '../services/vehicle.service';
import type {
  AdminRegisterVehicleInput,
  AdminUpdateVehicleInput,
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

export async function residentRegisterVehicleHandler(_req: Request, _res: Response): Promise<void> {
  assertResidentVehicleReadOnly();
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

export async function residentUpdateVehicleHandler(_req: Request, _res: Response): Promise<void> {
  assertResidentVehicleReadOnly();
}

export async function residentDeactivateVehicleHandler(
  _req: Request,
  _res: Response,
): Promise<void> {
  assertResidentVehicleReadOnly();
}

export async function adminListVehiclesHandler(req: Request, res: Response): Promise<void> {
  const data = await listAdminVehicles(societyId(req), {
    flatId: req.query.flatId as string | undefined,
    registeredUserId: req.query.registeredUserId as string | undefined,
    isActive: req.query.isActive as boolean | undefined,
    registrationNumber: req.query.registrationNumber as string | undefined,
    page: Number(req.query.page ?? 1),
    limit: Number(req.query.limit ?? 20),
  });
  res.json({ success: true, data });
}

export async function adminRegisterVehicleHandler(req: Request, res: Response): Promise<void> {
  const data = await adminRegisterVehicle(
    societyId(req),
    req.body as AdminRegisterVehicleInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function adminUpdateVehicleHandler(req: Request, res: Response): Promise<void> {
  const data = await adminUpdateVehicle(
    societyId(req),
    String(req.params.vehicleId),
    req.body as AdminUpdateVehicleInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function adminDeactivateVehicleHandler(req: Request, res: Response): Promise<void> {
  const data = await adminDeactivateVehicle(
    societyId(req),
    String(req.params.vehicleId),
    (req.body as { reason?: string }).reason,
    actorFrom(req),
  );
  res.json({ success: true, data });
}
