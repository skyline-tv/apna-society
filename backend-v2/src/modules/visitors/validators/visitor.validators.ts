import { z } from 'zod';
import { isObjectId } from '../../../utils/object-id';
import { APPROVAL_STATUSES, ENTRY_STATUSES, VISITOR_TYPES } from '../models/visitor-log.model';

const objectId = z.string().refine(isObjectId, 'Must be a valid ObjectId');

const phoneSchema = z
  .string()
  .trim()
  .min(7)
  .max(32)
  .regex(/^[+0-9\-\s()]+$/, 'Invalid phone number');

export const provisionGuardSchema = z
  .object({
    name: z.string().trim().min(1).max(120),
    email: z.string().trim().email().max(254),
    phone: phoneSchema.optional(),
  })
  .strict();

export const updateGuardSchema = z
  .object({
    name: z.string().trim().min(1).max(120).optional(),
    phone: phoneSchema.optional(),
    canLogin: z.boolean().optional(),
  })
  .strict()
  .refine((data) => Object.keys(data).length > 0, {
    message: 'At least one field is required',
  });

export const guardIdParamSchema = z.object({ guardId: objectId });

export const listGuardsQuerySchema = z.object({
  search: z.string().trim().max(120).optional(),
  isActive: z
    .enum(['true', 'false'])
    .optional()
    .transform((v) => (v === undefined ? undefined : v === 'true')),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const deactivateGuardSchema = z
  .object({
    reason: z.string().trim().min(3).max(500).optional(),
  })
  .strict();

export const createVisitorSchema = z
  .object({
    flatId: objectId,
    visitorName: z.string().trim().min(1).max(120),
    visitorPhone: phoneSchema,
    visitorEmail: z.string().trim().email().max(254).optional(),
    visitorType: z.enum(VISITOR_TYPES),
    purpose: z.string().trim().min(1).max(500),
    vehicleNumber: z.string().trim().max(32).optional(),
    numberOfVisitors: z.coerce.number().int().min(1).max(50).default(1),
    notes: z.string().trim().max(2000).optional(),
  })
  .strict();

export const visitorIdParamSchema = z.object({ visitorId: objectId });

export const listVisitorsQuerySchema = z.object({
  approvalStatus: z.enum(APPROVAL_STATUSES).optional(),
  entryStatus: z.enum(ENTRY_STATUSES).optional(),
  flatId: objectId.optional(),
  wingCode: z.string().trim().min(1).max(16).optional(),
  visitorType: z.enum(VISITOR_TYPES).optional(),
  visitorPhone: phoneSchema.optional(),
  visitorName: z.string().trim().max(120).optional(),
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const verifyEntryOtpSchema = z
  .object({
    otp: z.string().trim().regex(/^\d{6}$/, 'OTP must be 6 digits'),
  })
  .strict();

export const rejectVisitorSchema = z
  .object({
    reason: z.string().trim().min(1).max(500).optional(),
  })
  .strict();

export type ProvisionGuardInput = z.infer<typeof provisionGuardSchema>;
export type UpdateGuardInput = z.infer<typeof updateGuardSchema>;
export type CreateVisitorInput = z.infer<typeof createVisitorSchema>;
export type ListVisitorsQuery = z.infer<typeof listVisitorsQuerySchema>;
