import { z } from 'zod';
import { FLAT_TYPES, OCCUPANCY_STATUSES } from '../../../config/constants';
import { isObjectId } from '../../../utils/object-id';

const objectId = z.string().refine(isObjectId, 'Must be a valid ObjectId');

export const updateSocietySchema = z
  .object({
    name: z.string().trim().min(1).max(200).optional(),
    address: z.string().trim().max(500).optional(),
    city: z.string().trim().max(120).optional(),
    state: z.string().trim().max(120).optional(),
    pincode: z
      .string()
      .trim()
      .regex(/^[0-9A-Za-z\-\s]{3,16}$/, 'Invalid PIN code')
      .optional(),
    contactEmail: z.string().trim().email().max(254).optional(),
    contactPhone: z.string().trim().max(32).optional(),
    timezone: z.string().trim().min(1).max(64).optional(),
    currency: z.string().trim().min(3).max(8).optional(),
    maintenanceDayOfMonth: z.number().int().min(1).max(28).optional(),
    annualInterestRateBps: z.number().int().min(0).max(100_000).optional(),
    isActive: z.boolean().optional(),
  })
  .strict()
  .refine((data) => Object.keys(data).length > 0, {
    message: 'At least one field is required',
  });

export const createWingSchema = z
  .object({
    name: z.string().trim().min(1).max(120),
    code: z
      .string()
      .trim()
      .min(1)
      .max(16)
      .regex(/^[A-Za-z0-9]+$/, 'Wing code must be alphanumeric'),
    floors: z.number().int().min(1).max(200).default(7),
    flatsPerFloor: z.number().int().min(1).max(50).default(4),
    sortOrder: z.number().int().min(0).max(10_000).optional(),
    isActive: z.boolean().optional(),
  })
  .strict();

export const updateWingSchema = z
  .object({
    name: z.string().trim().min(1).max(120).optional(),
    code: z
      .string()
      .trim()
      .min(1)
      .max(16)
      .regex(/^[A-Za-z0-9]+$/, 'Wing code must be alphanumeric')
      .optional(),
    floors: z.number().int().min(1).max(200).optional(),
    flatsPerFloor: z.number().int().min(1).max(50).optional(),
    sortOrder: z.number().int().min(0).max(10_000).optional(),
    isActive: z.boolean().optional(),
  })
  .strict()
  .refine((data) => Object.keys(data).length > 0, {
    message: 'At least one field is required',
  });

export const wingIdParamSchema = z.object({
  wingId: objectId,
});

export const flatIdParamSchema = z.object({
  flatId: objectId,
});

const parkingSchema = z
  .object({
    hasParking: z.boolean(),
    slotLabel: z.string().trim().max(64).optional(),
  })
  .strict();

export const createFlatSchema = z
  .object({
    wingId: objectId,
    number: z
      .string()
      .trim()
      .min(1)
      .max(32)
      .transform((value) => value.toUpperCase()),
    floor: z.number().int().min(1).max(200),
    position: z.number().int().min(1).max(50),
    flatType: z.enum(FLAT_TYPES),
    maintenanceRate: z.number().min(0).max(1_000_000),
    isActive: z.boolean().optional(),
    parking: parkingSchema.optional(),
    notes: z.string().trim().max(2000).optional(),
  })
  .strict();

/**
 * Occupancy fields are intentionally absent. `.strict()` rejects
 * occupancyStatus / activeOwnerUserId / activeTenantUserId if submitted.
 */
export const updateFlatSchema = z
  .object({
    wingId: objectId.optional(),
    number: z
      .string()
      .trim()
      .min(1)
      .max(32)
      .transform((value) => value.toUpperCase())
      .optional(),
    floor: z.number().int().min(1).max(200).optional(),
    position: z.number().int().min(1).max(50).optional(),
    flatType: z.enum(FLAT_TYPES).optional(),
    maintenanceRate: z.number().min(0).max(1_000_000).optional(),
    isActive: z.boolean().optional(),
    parking: parkingSchema.optional(),
    notes: z.string().trim().max(2000).optional(),
    forceDeactivate: z.boolean().optional(),
    deactivationReason: z.string().trim().min(3).max(500).optional(),
  })
  .strict()
  .refine((data) => Object.keys(data).length > 0, {
    message: 'At least one field is required',
  });

export const listFlatsQuerySchema = z.object({
  wingId: objectId.optional(),
  floor: z.coerce.number().int().min(1).max(200).optional(),
  flatType: z.enum(FLAT_TYPES).optional(),
  occupancyStatus: z.enum(OCCUPANCY_STATUSES).optional(),
  isActive: z
    .enum(['true', 'false'])
    .optional()
    .transform((value) => (value === undefined ? undefined : value === 'true')),
  search: z.string().trim().max(64).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  sortBy: z
    .enum(['number', 'floor', 'position', 'maintenanceRate', 'createdAt', 'updatedAt'])
    .default('number'),
  sortOrder: z.enum(['asc', 'desc']).default('asc'),
});

export type UpdateSocietyInput = z.infer<typeof updateSocietySchema>;
export type CreateWingInput = z.infer<typeof createWingSchema>;
export type UpdateWingInput = z.infer<typeof updateWingSchema>;
export type CreateFlatInput = z.infer<typeof createFlatSchema>;
export type UpdateFlatInput = z.infer<typeof updateFlatSchema>;
export type ListFlatsQuery = z.infer<typeof listFlatsQuerySchema>;
