import type { Request, Response } from 'express';
import { forbidden, notFound } from '../../../shared/errors/app-error';
import { FlatModel } from '../../society/models/flat.model';
import { getFlatAccess } from '../../users/services/access-control.service';
import { VehicleModel } from '../models/vehicle.model';
import {
  allocateParkingSlot,
  getAllocation,
  listAllocations,
  listResidentParking,
  releaseParkingAllocation,
} from '../services/parking-allocation.service';
import {
  createParkingSlot,
  getParkingAvailabilitySummary,
  getParkingSlot,
  listParkingSlots,
  setParkingSlotActive,
  updateParkingSlot,
} from '../services/parking-slot.service';
import type {
  AllocateParkingInput,
  CreateParkingSlotInput,
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

export async function adminCreateSlotHandler(req: Request, res: Response): Promise<void> {
  const data = await createParkingSlot(
    societyId(req),
    req.body as CreateParkingSlotInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function adminListSlotsHandler(req: Request, res: Response): Promise<void> {
  const data = await listParkingSlots(societyId(req), {
    parkingType: req.query.parkingType as 'TWO_WHEELER' | 'FOUR_WHEELER' | 'OTHER' | undefined,
    isActive: req.query.isActive as boolean | undefined,
    availability: req.query.availability as 'available' | 'occupied' | 'all' | undefined,
    page: Number(req.query.page ?? 1),
    limit: Number(req.query.limit ?? 20),
  });
  res.json({ success: true, data });
}

export async function adminGetSlotHandler(req: Request, res: Response): Promise<void> {
  const data = await getParkingSlot(societyId(req), String(req.params.slotId));
  res.json({ success: true, data });
}

export async function adminUpdateSlotHandler(req: Request, res: Response): Promise<void> {
  const data = await updateParkingSlot(
    societyId(req),
    String(req.params.slotId),
    req.body as { locationDescription?: string; parkingType?: 'TWO_WHEELER' | 'FOUR_WHEELER' | 'OTHER' },
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function adminSetSlotActiveHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as { isActive: boolean; reason?: string };
  const data = await setParkingSlotActive(
    societyId(req),
    String(req.params.slotId),
    body.isActive,
    body.reason,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function adminParkingSummaryHandler(req: Request, res: Response): Promise<void> {
  const data = await getParkingAvailabilitySummary(societyId(req));
  res.json({ success: true, data });
}

export async function adminAllocateHandler(req: Request, res: Response): Promise<void> {
  const data = await allocateParkingSlot(
    societyId(req),
    req.body as AllocateParkingInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function adminListAllocationsHandler(req: Request, res: Response): Promise<void> {
  const data = await listAllocations(societyId(req), {
    status: req.query.status as string | undefined,
    flatId: req.query.flatId as string | undefined,
    vehicleId: req.query.vehicleId as string | undefined,
    parkingSlotId: req.query.parkingSlotId as string | undefined,
    page: Number(req.query.page ?? 1),
    limit: Number(req.query.limit ?? 20),
  });
  res.json({ success: true, data });
}

export async function adminGetAllocationHandler(req: Request, res: Response): Promise<void> {
  const data = await getAllocation(societyId(req), String(req.params.allocationId));
  res.json({ success: true, data });
}

export async function adminReleaseAllocationHandler(req: Request, res: Response): Promise<void> {
  const data = await releaseParkingAllocation(
    societyId(req),
    String(req.params.allocationId),
    (req.body as { reason?: string }).reason,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function residentListParkingHandler(req: Request, res: Response): Promise<void> {
  const society = societyId(req);
  const flats = await FlatModel.find({
    societyId: society,
    isActive: true,
    $or: [
      { activeOwnerUserId: req.user!.id },
      { activeTenantUserId: req.user!.id },
    ],
  })
    .select('_id')
    .lean();

  const residentialFlatIds: string[] = [];
  for (const flat of flats) {
    const access = await getFlatAccess({
      userId: req.user!.id,
      societyId: society,
      flatId: String(flat._id),
    });
    if (access.residential) residentialFlatIds.push(String(flat._id));
  }

  const data = await listResidentParking(society, residentialFlatIds, req.user!.id);
  res.json({ success: true, data });
}

export async function residentGetParkingAllocationHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const society = societyId(req);
  const allocation = await getAllocation(society, String(req.params.allocationId));

  const vehicle = await VehicleModel.findById(allocation.vehicleId)
    .select('registeredUserId')
    .lean();
  if (!vehicle || String(vehicle.registeredUserId) !== req.user!.id) {
    throw notFound('Allocation not found');
  }

  const access = await getFlatAccess({
    userId: req.user!.id,
    societyId: society,
    flatId: allocation.flatId,
  });
  if (!access.residential) {
    throw forbidden(
      'Residential access denied for this parking allocation',
      'RESIDENTIAL_ACCESS_DENIED',
    );
  }

  const slot = await getParkingSlot(society, allocation.parkingSlotId);
  res.json({ success: true, data: { ...allocation, slot } });
}
