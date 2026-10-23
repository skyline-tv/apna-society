import { z } from 'zod';
import {
  COLLECTION_AMOUNT_MODES,
  COLLECTION_ASSIGNMENT_TYPES,
  COLLECTION_STATUSES,
} from '../models/collection.model';
import { COLLECTION_CHARGE_STATUSES } from '../models/collection-charge.model';
import { PAYMENT_STATUSES } from '../../billing/models/payment.model';

const objectId = z.string().regex(/^[a-f\d]{24}$/i, 'Invalid ObjectId');

const flatAmountSchema = z.object({
  flatId: objectId,
  amountPaise: z.number().int().positive(),
});

export const previewCollectionSchema = z
  .object({
    title: z.string().trim().min(3).max(200),
    description: z.string().trim().min(3).max(4000),
    amountMode: z.enum(COLLECTION_AMOUNT_MODES),
    assignmentType: z.enum(COLLECTION_ASSIGNMENT_TYPES),
    amountPaise: z.number().int().min(0).optional(),
    wingIds: z.array(objectId).max(20).optional(),
    flatIds: z.array(objectId).max(200).optional(),
    flatAmounts: z.array(flatAmountSchema).max(200).optional(),
    dueDate: z.coerce.date(),
    startDate: z.coerce.date().optional(),
    paymentInstructions: z.string().trim().max(2000).optional(),
    allowPartialPayment: z.boolean().optional().default(false),
  })
  .strict()
  .superRefine((data, ctx) => {
    if (data.amountMode !== 'CUSTOM' && !(data.amountPaise && data.amountPaise > 0)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'amountPaise is required unless amountMode is CUSTOM',
        path: ['amountPaise'],
      });
    }
    if (data.assignmentType === 'WINGS' && !(data.wingIds?.length)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'wingIds required for WINGS assignment',
        path: ['wingIds'],
      });
    }
    if (data.assignmentType === 'SELECTED_FLATS' && !(data.flatIds?.length || data.flatAmounts?.length)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'flatIds or flatAmounts required for SELECTED_FLATS',
        path: ['flatIds'],
      });
    }
    if (data.amountMode === 'CUSTOM' && !(data.flatAmounts?.length)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'flatAmounts required for CUSTOM amounts',
        path: ['flatAmounts'],
      });
    }
  });
export type PreviewCollectionInput = z.infer<typeof previewCollectionSchema>;
export const createCollectionSchema = previewCollectionSchema;
export type CreateCollectionInput = PreviewCollectionInput;

export const updateCollectionSchema = z
  .object({
    title: z.string().trim().min(3).max(200).optional(),
    description: z.string().trim().min(3).max(4000).optional(),
    dueDate: z.coerce.date().optional(),
    startDate: z.coerce.date().nullable().optional(),
    paymentInstructions: z.string().trim().max(2000).nullable().optional(),
    allowPartialPayment: z.boolean().optional(),
  })
  .strict()
  .refine((data) => Object.keys(data).length > 0, {
    message: 'At least one field is required',
  });
export type UpdateCollectionInput = z.infer<typeof updateCollectionSchema>;

export const cancelCollectionSchema = z.object({
  reason: z.string().trim().min(3).max(500),
});
export type CancelCollectionInput = z.infer<typeof cancelCollectionSchema>;

export const adjustChargeSchema = z.object({
  deltaPaise: z.number().int().refine((v) => v !== 0, 'deltaPaise cannot be zero'),
  reason: z.string().trim().min(3).max(500),
});
export type AdjustChargeInput = z.infer<typeof adjustChargeSchema>;

export const collectionIdParamSchema = z.object({ collectionId: objectId });
export const chargeIdParamSchema = z.object({ chargeId: objectId });
export const collectionPaymentIdParamSchema = z.object({ paymentId: objectId });
export const collectionReceiptIdParamSchema = z.object({ receiptId: objectId });

export const listCollectionsQuerySchema = z.object({
  status: z.enum(COLLECTION_STATUSES).optional(),
  search: z.string().trim().max(80).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
export type ListCollectionsQuery = z.infer<typeof listCollectionsQuerySchema>;

export const listChargesQuerySchema = z.object({
  wingCode: z.string().trim().max(16).optional(),
  flatId: objectId.optional(),
  search: z.string().trim().max(80).optional(),
  status: z.enum([...COLLECTION_CHARGE_STATUSES, 'OVERDUE']).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(200).default(50),
});
export type ListChargesQuery = z.infer<typeof listChargesQuerySchema>;

export const listCollectionPaymentsQuerySchema = z.object({
  status: z.enum(PAYMENT_STATUSES).optional(),
  chargeId: objectId.optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
export type ListCollectionPaymentsQuery = z.infer<typeof listCollectionPaymentsQuerySchema>;

export const createCollectionPaymentOrderSchema = z.object({
  amountPaise: z.number().int().positive().optional(),
});
export type CreateCollectionPaymentOrderInput = z.infer<typeof createCollectionPaymentOrderSchema>;

export const verifyCollectionPaymentSchema = z.object({
  orderId: z.string().trim().min(1).max(120),
  paymentId: z.string().trim().min(1).max(120),
  signature: z.string().trim().min(1).max(256),
});
export type VerifyCollectionPaymentInput = z.infer<typeof verifyCollectionPaymentSchema>;

export const completeCollectionDemoSchema = z.object({
  orderId: z.string().trim().min(1).max(120),
  outcome: z.enum(['success', 'failure']),
});
export type CompleteCollectionDemoInput = z.infer<typeof completeCollectionDemoSchema>;

export const offlineCollectionPaymentSchema = z.object({
  chargeId: objectId,
  amountPaise: z.number().int().positive(),
  paidAt: z.coerce.date(),
  referenceNumber: z.string().trim().min(1).max(120),
  notes: z.string().trim().max(2000).optional(),
  idempotencyKey: z.string().trim().min(1).max(120).optional(),
});
export type OfflineCollectionPaymentInput = z.infer<typeof offlineCollectionPaymentSchema>;
