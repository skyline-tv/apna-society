import { z } from 'zod';
import { isObjectId } from '../../../utils/object-id';
import { PAYMENT_METHODS, PAYMENT_STATUSES } from '../../billing/models/payment.model';

const objectId = z.string().refine(isObjectId, 'Must be a valid ObjectId');

const baseFilters = {
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  wingCode: z
    .string()
    .trim()
    .min(1)
    .max(16)
    .transform((v) => v.toUpperCase())
    .optional(),
  wingId: objectId.optional(),
  flatId: objectId.optional(),
};

export const financialReportQuerySchema = z.object({
  ...baseFilters,
  paymentMethod: z.enum(PAYMENT_METHODS).optional(),
  paymentStatus: z.enum(PAYMENT_STATUSES).optional(),
});

export type FinancialReportQueryInput = z.infer<typeof financialReportQuerySchema>;

export const collectionReportQuerySchema = z.object({
  ...baseFilters,
});

export const outstandingReportQuerySchema = z.object({
  ...baseFilters,
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(200).default(50),
});

export const complaintAnalyticsQuerySchema = z.object({
  ...baseFilters,
});

export const dashboardReportQuerySchema = z.object({
  ...baseFilters,
});

export const exportTypeParamSchema = z.object({
  type: z.enum(['financial', 'collections', 'outstanding', 'payments', 'complaints']),
});

export const exportQuerySchema = z.object({
  ...baseFilters,
  paymentMethod: z.enum(PAYMENT_METHODS).optional(),
  paymentStatus: z.enum(PAYMENT_STATUSES).optional(),
  format: z.enum(['csv']).default('csv'),
});
