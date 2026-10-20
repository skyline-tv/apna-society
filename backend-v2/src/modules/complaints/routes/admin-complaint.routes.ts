import { Router } from 'express';
import { complaintUploadRateLimiter } from '../../../middleware/rate-limit';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  adminAssignHandler,
  adminCancelHandler,
  adminCategoriesHandler,
  adminCloseHandler,
  adminDownloadAttachmentHandler,
  adminGetComplaintHandler,
  adminListComplaintsHandler,
  adminResolveHandler,
  adminStartHandler,
  adminSummaryHandler,
  adminUnassignHandler,
  adminUpdatePriorityHandler,
  adminUploadAttachmentHandler,
} from '../controllers/complaint.controller';
import { complaintAttachmentUpload } from '../middleware/upload';
import {
  adminCancelComplaintSchema,
  assignComplaintSchema,
  attachmentIdParamSchema,
  complaintIdParamSchema,
  listComplaintsQuerySchema,
  resolveComplaintSchema,
  summaryQuerySchema,
  unassignComplaintSchema,
  updatePrioritySchema,
} from '../validators/complaint.validators';

const router = Router();

router.get('/complaints/categories', asyncHandler(adminCategoriesHandler));
router.get(
  '/complaints/summary',
  validateQuery(summaryQuerySchema),
  asyncHandler(adminSummaryHandler),
);
router.get(
  '/complaints',
  validateQuery(listComplaintsQuerySchema),
  asyncHandler(adminListComplaintsHandler),
);
router.get(
  '/complaints/:complaintId',
  validateParams(complaintIdParamSchema),
  asyncHandler(adminGetComplaintHandler),
);
router.patch(
  '/complaints/:complaintId/priority',
  validateParams(complaintIdParamSchema),
  validateBody(updatePrioritySchema),
  asyncHandler(adminUpdatePriorityHandler),
);
router.post(
  '/complaints/:complaintId/assign',
  validateParams(complaintIdParamSchema),
  validateBody(assignComplaintSchema),
  asyncHandler(adminAssignHandler),
);
router.post(
  '/complaints/:complaintId/unassign',
  validateParams(complaintIdParamSchema),
  validateBody(unassignComplaintSchema),
  asyncHandler(adminUnassignHandler),
);
router.post(
  '/complaints/:complaintId/start',
  validateParams(complaintIdParamSchema),
  asyncHandler(adminStartHandler),
);
router.post(
  '/complaints/:complaintId/resolve',
  validateParams(complaintIdParamSchema),
  validateBody(resolveComplaintSchema),
  asyncHandler(adminResolveHandler),
);
router.post(
  '/complaints/:complaintId/close',
  validateParams(complaintIdParamSchema),
  asyncHandler(adminCloseHandler),
);
router.post(
  '/complaints/:complaintId/cancel',
  validateParams(complaintIdParamSchema),
  validateBody(adminCancelComplaintSchema),
  asyncHandler(adminCancelHandler),
);
router.post(
  '/complaints/:complaintId/attachments',
  complaintUploadRateLimiter,
  validateParams(complaintIdParamSchema),
  complaintAttachmentUpload,
  asyncHandler(adminUploadAttachmentHandler),
);
router.get(
  '/complaints/:complaintId/attachments/:attachmentId',
  validateParams(attachmentIdParamSchema),
  asyncHandler(adminDownloadAttachmentHandler),
);

export default router;
