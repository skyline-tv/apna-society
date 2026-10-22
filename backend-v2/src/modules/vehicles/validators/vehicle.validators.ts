import { z } from 'zod';
import { isObjectId } from '../../../utils/object-id';
import { ALLOCATION_STATUSES } from '../models/parking-allocation.model';
import { VEHICLE_LOG_STATUSES } from '../models/vehicle-log.model';
import { VEHICLE_TYPES } from '../models/vehicle.model';

const objectId = z.string().refine(isObjectId, 'Must be a valid ObjectId');

const optionalParkingNumber = z
  .string()
  .trim()
  .max(32)
  .optional()
  .transform((v) => (v && v.length > 0 ? v : undefined));

export const vehicleDraftSchema = z
  .object({
    vehicleType: z.enum(VEHICLE_TYPES),
    registrationNumber: z.string().trim().min(6).max(20),
    make: z.string().trim().min(1).max(80).optional(),
    model: z.string().trim().min(1).max(80).optional(),
    colour: z.string().trim().min(1).max(40).optional(),
    parkingNumber: optionalParkingNumber,
  })
  .strict();

export const vehicleDraftListSchema = z.array(vehicleDraftSchema).max(10);

export const registerVehicleSchema = vehicleDraftSchema
  .extend({
    flatId: objectId,
  })
  .strict();

export const adminRegisterVehicleSchema = vehicleDraftSchema
  .extend({
    flatId: objectId,
    registeredUserId: objectId,
  })
  .strict();

export const updateVehicleSchema = z
  .object({
    make: z.string().trim().min(1).max(80).optional(),
    model: z.string().trim().min(1).max(80).optional(),
    colour: z.string().trim().min(1).max(40).optional(),
    vehicleType: z.enum(VEHICLE_TYPES).optional(),
  })
  .strict()
  .refine((data) => Object.keys(data).length > 0, {
    message: 'At least one field is required',
  });

export const adminUpdateVehicleSchema = z
  .object({
    make: z.string().trim().min(1).max(80).optional(),
    model: z.string().trim().min(1).max(80).optional(),
    colour: z.string().trim().min(1).max(40).optional(),
    vehicleType: z.enum(VEHICLE_TYPES).optional(),
    registrationNumber: z.string().trim().min(6).max(20).optional(),
    parkingNumber: z
      .string()
      .trim()
      .max(32)
      .nullable()
      .optional()
      .transform((v) => (v == null || v === '' ? null : v)),
  })
  .strict()
  .refine((data) => Object.keys(data).length > 0, {
    message: 'At least one field is required',
  });

export const deactivateVehicleSchema = z
  .object({
    reason: z.string().trim().min(1).max(500).optional(),
  })
  .strict();

export const vehicleIdParamSchema = z.object({ vehicleId: objectId });

export const listAdminVehiclesQuerySchema = z.object({
  flatId: objectId.optional(),
  registeredUserId: objectId.optional(),
  isActive: z
    .enum(['true', 'false'])
    .optional()
    .transform((v) => (v === undefined ? undefined : v === 'true')),
  registrationNumber: z.string().trim().max(20).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const createParkingSlotSchema = z
  .object({
    slotNumber: z.string().trim().min(1).max(32),
    parkingType: z.enum(VEHICLE_TYPES),
    locationDescription: z.string().trim().min(1).max(200).optional(),
  })
  .strict();

export const updateParkingSlotSchema = z
  .object({
    locationDescription: z.string().trim().min(1).max(200).optional(),
    parkingType: z.enum(VEHICLE_TYPES).optional(),
  })
  .strict()
  .refine((data) => Object.keys(data).length > 0, {
    message: 'At least one field is required',
  });

export const setParkingSlotActiveSchema = z
  .object({
    isActive: z.boolean(),
    reason: z.string().trim().min(1).max(500).optional(),
  })
  .strict();

export const slotIdParamSchema = z.object({ slotId: objectId });

export const listParkingSlotsQuerySchema = z.object({
  parkingType: z.enum(VEHICLE_TYPES).optional(),
  isActive: z
    .enum(['true', 'false'])
    .optional()
    .transform((v) => (v === undefined ? undefined : v === 'true')),
  availability: z.enum(['available', 'occupied', 'all']).optional().default('all'),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const allocateParkingSchema = z
  .object({
    flatId: objectId,
    vehicleId: objectId,
    parkingSlotId: objectId,
    startsAt: z.coerce.date().optional(),
  })
  .strict();

export const releaseAllocationSchema = z
  .object({
    reason: z.string().trim().min(1).max(500).optional(),
  })
  .strict();

export const allocationIdParamSchema = z.object({ allocationId: objectId });

export const listAllocationsQuerySchema = z.object({
  status: z.enum(ALLOCATION_STATUSES).optional(),
  flatId: objectId.optional(),
  vehicleId: objectId.optional(),
  parkingSlotId: objectId.optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const vehicleEntrySchema = z
  .object({
    registrationNumber: z.string().trim().min(6).max(20),
    vehicleType: z.enum(VEHICLE_TYPES).optional(),
    vehicleId: objectId.optional(),
    notes: z.string().trim().max(1000).optional(),
  })
  .strict();

export const vehicleExitSchema = z
  .object({
    logId: objectId.optional(),
    registrationNumber: z.string().trim().min(6).max(20).optional(),
  })
  .strict()
  .refine((data) => Boolean(data.logId || data.registrationNumber), {
    message: 'logId or registrationNumber is required',
  });

export const listVehicleLogsQuerySchema = z.object({
  status: z.enum(VEHICLE_LOG_STATUSES).optional(),
  registrationNumber: z.string().trim().max(20).optional(),
  vehicleId: objectId.optional(),
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export type VehicleDraftInput = z.infer<typeof vehicleDraftSchema>;
export type RegisterVehicleInput = z.infer<typeof registerVehicleSchema>;
export type AdminRegisterVehicleInput = z.infer<typeof adminRegisterVehicleSchema>;
export type UpdateVehicleInput = z.infer<typeof updateVehicleSchema>;
export type AdminUpdateVehicleInput = z.infer<typeof adminUpdateVehicleSchema>;
export type CreateParkingSlotInput = z.infer<typeof createParkingSlotSchema>;
export type AllocateParkingInput = z.infer<typeof allocateParkingSchema>;
export type VehicleEntryInput = z.infer<typeof vehicleEntrySchema>;
export type VehicleExitInput = z.infer<typeof vehicleExitSchema>;
