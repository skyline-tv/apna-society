import { z } from 'zod';
import { isObjectId } from '../../../utils/object-id';

const objectId = z.string().refine(isObjectId, 'Must be a valid ObjectId');

export const assignOccupancySchema = z
  .object({
    userId: objectId,
    effectiveFrom: z.coerce.date(),
    notes: z.string().trim().max(1000).optional(),
  })
  .strict();

export const endOccupancySchema = z
  .object({
    effectiveTo: z.coerce.date(),
    reason: z.string().trim().min(3).max(500),
    notes: z.string().trim().max(1000).optional(),
  })
  .strict();

export const occupancyHistoryQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

export const listOccupanciesQuerySchema = z.object({
  status: z.enum(['ACTIVE', 'ENDED']).optional(),
  role: z.enum(['OWNER', 'TENANT']).optional(),
  flatId: objectId.optional(),
  userId: objectId.optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export type AssignOccupancyBody = z.infer<typeof assignOccupancySchema>;
export type EndOccupancyBody = z.infer<typeof endOccupancySchema>;
