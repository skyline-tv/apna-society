import { z } from 'zod';

const objectId = z.string().regex(/^[a-f\d]{24}$/i, 'Invalid ObjectId');

export const createAdditionalServiceSchema = z
  .object({
    flatId: objectId,
    name: z.string().trim().min(1).max(120),
    description: z.string().trim().max(500).optional(),
    monthlyChargePaise: z.number().int().min(0).max(10_000_000),
    quantity: z.number().int().min(1).max(99).default(1),
    effectiveFrom: z.coerce.date(),
    effectiveTo: z.coerce.date().optional(),
    isActive: z.boolean().optional(),
  })
  .superRefine((data, ctx) => {
    if (data.effectiveTo && data.effectiveTo.getTime() < data.effectiveFrom.getTime()) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'effectiveTo must be on or after effectiveFrom',
        path: ['effectiveTo'],
      });
    }
  });
export type CreateAdditionalServiceInput = z.infer<typeof createAdditionalServiceSchema>;

export const updateAdditionalServiceSchema = z
  .object({
    name: z.string().trim().min(1).max(120).optional(),
    description: z.string().trim().max(500).optional(),
    monthlyChargePaise: z.number().int().min(0).max(10_000_000).optional(),
    quantity: z.number().int().min(1).max(99).optional(),
    effectiveFrom: z.coerce.date().optional(),
    effectiveTo: z.coerce.date().nullable().optional(),
    isActive: z.boolean().optional(),
  })
  .refine((data) => Object.keys(data).length > 0, {
    message: 'At least one field is required',
  });
export type UpdateAdditionalServiceInput = z.infer<typeof updateAdditionalServiceSchema>;

export const listAdditionalServicesQuerySchema = z.object({
  flatId: objectId.optional(),
  wingId: objectId.optional(),
  isActive: z
    .enum(['true', 'false'])
    .optional()
    .transform((v) => (v === undefined ? undefined : v === 'true')),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(200).default(50),
});
export type ListAdditionalServicesQuery = z.infer<typeof listAdditionalServicesQuerySchema>;

export const additionalServiceIdParamSchema = z.object({
  serviceId: objectId,
});

export const deactivateAdditionalServiceSchema = z.object({
  reason: z.string().trim().max(500).optional(),
  effectiveTo: z.coerce.date().optional(),
});
export type DeactivateAdditionalServiceInput = z.infer<typeof deactivateAdditionalServiceSchema>;
