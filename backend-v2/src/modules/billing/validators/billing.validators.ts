import { z } from 'zod';
import { OCCUPANCY_STATUSES } from '../../../config/constants';
import { BILL_STATUSES } from '../models/bill.model';
import { OFFICE_PAYMENT_METHODS, PAYMENT_STATUSES } from '../models/payment.model';

const optionalBoolQuery = z
  .enum(['true', 'false'])
  .optional()
  .transform((v) => (v === undefined ? undefined : v === 'true'));

const objectId = z.string().regex(/^[a-f\d]{24}$/i, 'Invalid ObjectId');

export const generateBillsSchema = z.object({
  billingPeriodStart: z.coerce.date(),
  numberOfMonths: z.union([z.literal(1), z.literal(3)]),
  dueDate: z.coerce.date().optional(),
  notes: z.string().trim().max(2000).optional(),
});
export type GenerateBillsInput = z.infer<typeof generateBillsSchema>;

export const listBillsQuerySchema = z.object({
  status: z.enum(BILL_STATUSES).optional(),
  flatId: objectId.optional(),
  ownerUserId: objectId.optional(),
  wingCode: z.string().trim().min(1).max(10).optional(),
  billingPeriodStart: z.coerce.date().optional(),
  occupancyStatus: z.enum(OCCUPANCY_STATUSES).optional(),
  floor: z.coerce.number().int().min(0).max(200).optional(),
  ownerAssigned: optionalBoolQuery,
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(200).default(20),
});
export type ListBillsQuery = z.infer<typeof listBillsQuerySchema>;

export const billIdParamSchema = z.object({
  billId: objectId,
});

export const paymentIdParamSchema = z.object({
  paymentId: objectId,
});

export const receiptIdParamSchema = z.object({
  receiptId: objectId,
});

export const billingSummaryQuerySchema = z.object({
  billingPeriodStart: z.coerce.date().optional(),
  wingCode: z.string().trim().min(1).max(10).optional(),
  flatId: objectId.optional(),
  status: z.enum(BILL_STATUSES).optional(),
  ownerUserId: objectId.optional(),
  paymentStatus: z.enum(PAYMENT_STATUSES).optional(),
  occupancyStatus: z.enum(OCCUPANCY_STATUSES).optional(),
  floor: z.coerce.number().int().min(0).max(200).optional(),
  ownerAssigned: optionalBoolQuery,
});
export type BillingSummaryQuery = z.infer<typeof billingSummaryQuerySchema>;

export const interestQuerySchema = z.object({
  asOf: z.coerce.date().optional(),
});

export const adjustBillSchema = z.object({
  adjustmentsPaise: z.number().int(),
  notes: z.string().trim().max(2000).optional(),
});
export type AdjustBillInput = z.infer<typeof adjustBillSchema>;

export const cancelBillSchema = z.object({
  reason: z.string().trim().min(1).max(500),
});

export const offlinePaymentSchema = z.object({
  billId: objectId,
  amountPaise: z.number().int().positive(),
  paidAt: z.coerce.date(),
  paymentMethod: z.enum(OFFICE_PAYMENT_METHODS).optional(),
  referenceNumber: z.string().trim().min(1).max(120),
  notes: z.string().trim().max(2000).optional(),
  idempotencyKey: z.string().trim().min(1).max(120).optional(),
});
export type OfflinePaymentInput = z.infer<typeof offlinePaymentSchema>;

export const listPaymentsQuerySchema = z.object({
  status: z.enum(PAYMENT_STATUSES).optional(),
  billId: objectId.optional(),
  ownerUserId: objectId.optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
export type ListPaymentsQuery = z.infer<typeof listPaymentsQuerySchema>;

export const verifyPaymentSchema = z.object({
  orderId: z.string().trim().min(1).max(120),
  paymentId: z.string().trim().min(1).max(120),
  signature: z.string().trim().min(1).max(256),
});
export type VerifyPaymentInput = z.infer<typeof verifyPaymentSchema>;

/** Non-production mock checkout completion — server signs/settles; clients send no HMAC. */
export const completeDemoPaymentSchema = z.object({
  orderId: z.string().trim().min(1).max(120),
  outcome: z.enum(['success', 'failure']),
});
export type CompleteDemoPaymentInput = z.infer<typeof completeDemoPaymentSchema>;

export const refundPaymentSchema = z.object({
  reason: z.string().trim().min(1).max(500),
});

export const listReceiptsQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
