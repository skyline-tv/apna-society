import { z } from 'zod';
import { isObjectId } from '../../../utils/object-id';
import { PASSWORD_MAX_LENGTH, PASSWORD_MIN_LENGTH } from '../../../utils/password';
import { USERNAME_MAX_LENGTH, USERNAME_MIN_LENGTH } from '../../../utils/username';
import { vehicleDraftListSchema } from '../../vehicles/validators/vehicle.validators';

const objectId = z.string().refine(isObjectId, 'Must be a valid ObjectId');

const residentRole = z.enum(['OWNER', 'TENANT']);

const phoneSchema = z
  .string()
  .trim()
  .min(7)
  .max(32)
  .regex(/^[+0-9\-\s()]+$/, 'Invalid phone number');

const usernameSchema = z
  .string()
  .trim()
  .min(USERNAME_MIN_LENGTH)
  .max(USERNAME_MAX_LENGTH)
  .regex(/^[a-zA-Z0-9][a-zA-Z0-9_-]*$/, 'Invalid username');

const passwordSchema = z.string().min(PASSWORD_MIN_LENGTH).max(PASSWORD_MAX_LENGTH);

export const provisionUserSchema = z
  .object({
    name: z.string().trim().min(1).max(120),
    email: z.string().trim().email().max(254),
    phone: phoneSchema.optional(),
    role: residentRole,
    /** When omitted, derived from the email local-part (still unique). */
    username: usernameSchema.optional(),
    /** Optional admin-chosen password; otherwise a temporary password is generated. */
    password: passwordSchema.optional(),
    /** Optional flat assignment at provision time. Required when vehicles are sent. */
    flatId: objectId.optional(),
    vehicles: vehicleDraftListSchema.optional(),
  })
  .strict()
  .refine((data) => !data.vehicles?.length || Boolean(data.flatId), {
    message: 'Assign a flat to register vehicles',
    path: ['flatId'],
  });

export const updateUserSchema = z
  .object({
    name: z.string().trim().min(1).max(120).optional(),
    phone: phoneSchema.optional(),
    canLogin: z.boolean().optional(),
    isActive: z.boolean().optional(),
    username: usernameSchema.optional(),
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

export const setUserMobileSchema = z
  .object({
    mobile: z.string().trim().min(8).max(20),
  })
  .strict();

export const adminSetPasswordSchema = z
  .object({
    /** When omitted, a secure temporary password is generated and returned once. */
    password: passwordSchema.optional(),
    mustChangePassword: z.boolean().default(true),
  })
  .strict();

export type ProvisionUserInput = z.infer<typeof provisionUserSchema>;
export type UpdateUserInput = z.infer<typeof updateUserSchema>;
export type ListUsersQuery = z.infer<typeof listUsersQuerySchema>;
export type SetUserMobileInput = z.infer<typeof setUserMobileSchema>;
export type AdminSetPasswordInput = z.infer<typeof adminSetPasswordSchema>;
