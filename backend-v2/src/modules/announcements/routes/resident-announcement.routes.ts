import { Router } from 'express';
import { resolveResidentSociety } from '../../../middleware/resident-society';
import { validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  residentDownloadAnnouncementAttachmentHandler,
  residentGetAnnouncementHandler,
  residentListAnnouncementsHandler,
  residentMarkAnnouncementReadHandler,
  residentMarkAnnouncementUnreadHandler,
  residentUnreadAnnouncementCountHandler,
} from '../controllers/announcement.controller';
import {
  announcementAttachmentParamSchema,
  announcementIdParamSchema,
  listResidentAnnouncementsQuerySchema,
} from '../validators/announcement.validators';

const router = Router();

router.use(resolveResidentSociety);

router.get(
  '/announcements/unread-count',
  asyncHandler(residentUnreadAnnouncementCountHandler),
);
router.get(
  '/announcements',
  validateQuery(listResidentAnnouncementsQuerySchema),
  asyncHandler(residentListAnnouncementsHandler),
);
router.get(
  '/announcements/:announcementId',
  validateParams(announcementIdParamSchema),
  asyncHandler(residentGetAnnouncementHandler),
);
router.post(
  '/announcements/:announcementId/read',
  validateParams(announcementIdParamSchema),
  asyncHandler(residentMarkAnnouncementReadHandler),
);
router.post(
  '/announcements/:announcementId/unread',
  validateParams(announcementIdParamSchema),
  asyncHandler(residentMarkAnnouncementUnreadHandler),
);
router.get(
  '/announcements/:announcementId/attachments/:attachmentId',
  validateParams(announcementAttachmentParamSchema),
  asyncHandler(residentDownloadAnnouncementAttachmentHandler),
);

export default router;
