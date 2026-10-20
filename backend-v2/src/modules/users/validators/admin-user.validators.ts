import { z } from 'zod';
import { isObjectId } from '../../../utils/object-id';

const objectId = z.string().refine(isObjectId, 'Must be a valid ObjectId');

const residentRole = z.enum(['OWNER', 'TENANT']);

const phoneSchema = z
  .string()
  .trim()
  .min(7)
  .max(32)
  .regex(/^[+0-9\-\s()]+$/, 'Invalid phone number');

export const provisionUserSchema = z
  .object({
    name: z.string().trim().min(1).max(120),
    email: z.string().trim().email().max(254),
    phone: phoneSchema.optional(),
    role: residentRole,
  })
  .strict();

export const updateUserSchema = z
  .object({
    name: z.string().trim().min(1).max(120).optional(),
    phone: phoneSchema.optional(),
    canLogin: z.boolean().optional(),
    isActive: z.boolean().optional(),
  })
  .strict()
  .refine((data) => Object.keys(data).length > 0, {
    message: 'At least one field is required',
  });

export const userIdParamSchema = z.object({
  userId: objectId,
});

export const listUsersQuerySchema = z.object({
  search: z.string().trim().max(120).optional(),
  role: z.enum(['OWNER', 'TENANT', 'ADMIN', 'GUARD']).optional(),
  isActive: z
    .enum(['true', 'false'])
    .optional()
    .transform((value) => (value === undefined ? undefined : value === 'true')),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const deactivateUserSchema = z
  .object({
    reason: z.string().trim().min(3).max(500).optional(),
  })
  .strict();

export type ProvisionUserInput = z.infer<typeof provisionUserSchema>;
export type UpdateUserInput = z.infer<typeof updateUserSchema>;
export type ListUsersQuery = z.infer<typeof listUsersQuerySchema>;
