import { Router } from 'express';
import {
  complaintCreateRateLimiter,
  complaintUploadRateLimiter,
} from '../../../middleware/rate-limit';
import { resolveResidentSociety } from '../../../middleware/resident-society';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  residentCancelComplaintHandler,
  residentCreateComplaintHandler,
  residentDownloadAttachmentHandler,
  residentGetComplaintHandler,
  residentListComplaintsHandler,
  residentUploadAttachmentHandler,
} from '../controllers/complaint.controller';
import { complaintAttachmentUpload } from '../middleware/upload';
import {
  attachmentIdParamSchema,
  cancelComplaintSchema,
  complaintIdParamSchema,
  createComplaintSchema,
  listComplaintsQuerySchema,
} from '../validators/complaint.validators';

const router = Router();

router.use(resolveResidentSociety);

router.post(
  '/complaints',
  complaintCreateRateLimiter,
  validateBody(createComplaintSchema),
  asyncHandler(residentCreateComplaintHandler),
);
router.get(
  '/complaints',
  validateQuery(listComplaintsQuerySchema),
  asyncHandler(residentListComplaintsHandler),
);
router.get(
  '/complaints/:complaintId',
  validateParams(complaintIdParamSchema),
  asyncHandler(residentGetComplaintHandler),
);
router.post(
  '/complaints/:complaintId/cancel',
  validateParams(complaintIdParamSchema),
  validateBody(cancelComplaintSchema),
  asyncHandler(residentCancelComplaintHandler),
);
router.post(
  '/complaints/:complaintId/attachments',
  complaintUploadRateLimiter,
  validateParams(complaintIdParamSchema),
  complaintAttachmentUpload,
  asyncHandler(residentUploadAttachmentHandler),
);
router.get(
  '/complaints/:complaintId/attachments/:attachmentId',
  validateParams(attachmentIdParamSchema),
  asyncHandler(residentDownloadAttachmentHandler),
);

export default router;
