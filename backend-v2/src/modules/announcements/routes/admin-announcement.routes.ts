import { Router } from 'express';
import {
  announcementPublishRateLimiter,
  announcementUploadRateLimiter,
} from '../../../middleware/rate-limit';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  adminAnnouncementSummaryHandler,
  adminArchiveAnnouncementHandler,
  adminCancelAnnouncementHandler,
  adminCreateAnnouncementHandler,
  adminDownloadAttachmentHandler,
  adminGetAnnouncementHandler,
  adminListAnnouncementsHandler,
  adminPublishAnnouncementHandler,
  adminRecipientsHandler,
  adminRemoveAttachmentHandler,
  adminScheduleAnnouncementHandler,
  adminUpdateAnnouncementHandler,
  adminUploadAttachmentHandler,
} from '../controllers/announcement.controller';
import { announcementAttachmentUpload } from '../middleware/upload';
import {
  announcementAttachmentParamSchema,
  announcementIdParamSchema,
  createAnnouncementSchema,
  listAdminAnnouncementsQuerySchema,
  scheduleAnnouncementSchema,
  updateAnnouncementSchema,
} from '../validators/announcement.validators';

const router = Router();

router.get('/announcements/summary', asyncHandler(adminAnnouncementSummaryHandler));
router.get(
  '/announcements',
  validateQuery(listAdminAnnouncementsQuerySchema),
  asyncHandler(adminListAnnouncementsHandler),
);
router.post(
  '/announcements',
  validateBody(createAnnouncementSchema),
  asyncHandler(adminCreateAnnouncementHandler),
);
router.get(
  '/announcements/:announcementId',
  validateParams(announcementIdParamSchema),
  asyncHandler(adminGetAnnouncementHandler),
);
router.patch(
  '/announcements/:announcementId',
  validateParams(announcementIdParamSchema),
  validateBody(updateAnnouncementSchema),
  asyncHandler(adminUpdateAnnouncementHandler),
);
router.post(
  '/announcements/:announcementId/publish',
  announcementPublishRateLimiter,
  validateParams(announcementIdParamSchema),
  asyncHandler(adminPublishAnnouncementHandler),
);
router.post(
  '/announcements/:announcementId/schedule',
  announcementPublishRateLimiter,
  validateParams(announcementIdParamSchema),
  validateBody(scheduleAnnouncementSchema),
  asyncHandler(adminScheduleAnnouncementHandler),
);
router.post(
  '/announcements/:announcementId/cancel',
  validateParams(announcementIdParamSchema),
  asyncHandler(adminCancelAnnouncementHandler),
);
router.post(
  '/announcements/:announcementId/archive',
  validateParams(announcementIdParamSchema),
  asyncHandler(adminArchiveAnnouncementHandler),
);
router.get(
  '/announcements/:announcementId/recipients',
  validateParams(announcementIdParamSchema),
  asyncHandler(adminRecipientsHandler),
);
router.post(
  '/announcements/:announcementId/attachments',
  announcementUploadRateLimiter,
  validateParams(announcementIdParamSchema),
  announcementAttachmentUpload,
  asyncHandler(adminUploadAttachmentHandler),
);
router.delete(
  '/announcements/:announcementId/attachments/:attachmentId',
  validateParams(announcementAttachmentParamSchema),
  asyncHandler(adminRemoveAttachmentHandler),
);
router.get(
  '/announcements/:announcementId/attachments/:attachmentId',
  validateParams(announcementAttachmentParamSchema),
  asyncHandler(adminDownloadAttachmentHandler),
);

export default router;
