import { z } from 'zod';
import { isObjectId } from '../../../utils/object-id';
import {
  COMPLAINT_CATEGORIES,
  COMPLAINT_PRIORITIES,
  COMPLAINT_STATUSES,
} from '../models/complaint.model';

const objectId = z.string().refine(isObjectId, 'Must be a valid ObjectId');

export const createComplaintSchema = z
  .object({
    flatId: objectId,
    category: z.enum(COMPLAINT_CATEGORIES),
    title: z.string().trim().min(3).max(160),
    description: z.string().trim().min(5).max(4000),
  })
  .strict();

export const complaintIdParamSchema = z.object({ complaintId: objectId });

export const attachmentIdParamSchema = z.object({
  complaintId: objectId,
  attachmentId: objectId,
});

export const listComplaintsQuerySchema = z.object({
  status: z.enum(COMPLAINT_STATUSES).optional(),
  category: z.enum(COMPLAINT_CATEGORIES).optional(),
  priority: z.enum(COMPLAINT_PRIORITIES).optional(),
  flatId: objectId.optional(),
  assignedToUserId: objectId.optional(),
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  sort: z.enum(['createdAt', '-createdAt', 'priority', '-priority']).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const cancelComplaintSchema = z
  .object({
    reason: z.string().trim().min(1).max(1000).optional(),
  })
  .strict();

export const adminCancelComplaintSchema = z
  .object({
    reason: z.string().trim().min(3).max(1000),
  })
  .strict();

export const updatePrioritySchema = z
  .object({
    priority: z.enum(COMPLAINT_PRIORITIES),
  })
  .strict();

export const assignComplaintSchema = z
  .object({
    assignmentType: z.enum(['INTERNAL', 'EXTERNAL']),
    assignedToUserId: objectId.optional(),
    externalAssignee: z
      .object({
        name: z.string().trim().min(1).max(120),
        phone: z.string().trim().min(7).max(32).optional(),
        company: z.string().trim().min(1).max(120).optional(),
      })
      .strict()
      .optional(),
    notes: z.string().trim().max(2000).optional(),
  })
  .strict()
  .superRefine((data, ctx) => {
    if (data.assignmentType === 'INTERNAL' && !data.assignedToUserId) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'assignedToUserId is required for INTERNAL assignment',
        path: ['assignedToUserId'],
      });
    }
    if (data.assignmentType === 'EXTERNAL' && !data.externalAssignee?.name) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'externalAssignee is required for EXTERNAL assignment',
        path: ['externalAssignee'],
      });
    }
  });

export const unassignComplaintSchema = z
  .object({
    reason: z.string().trim().min(1).max(1000).optional(),
  })
  .strict();

export const resolveComplaintSchema = z
  .object({
    resolutionNotes: z.string().trim().min(3).max(4000),
    internalNotes: z.string().trim().max(4000).optional(),
  })
  .strict();

export const summaryQuerySchema = z.object({
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
});

export type CreateComplaintInput = z.infer<typeof createComplaintSchema>;
export type AssignComplaintInput = z.infer<typeof assignComplaintSchema>;
export type ListComplaintsQuery = z.infer<typeof listComplaintsQuerySchema>;
