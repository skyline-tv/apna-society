import { Router } from 'express';
import { resolveResidentSociety } from '../../../middleware/resident-society';
import { validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  residentGetNotificationHandler,
  residentListNotificationsHandler,
  residentMarkAllNotificationsReadHandler,
  residentMarkNotificationReadHandler,
  residentMarkNotificationUnreadHandler,
  residentUnreadNotificationCountHandler,
} from '../controllers/notification.controller';
import {
  listNotificationsQuerySchema,
  notificationIdParamSchema,
} from '../../announcements/validators/announcement.validators';

const router = Router();

router.use(resolveResidentSociety);

router.get(
  '/notifications/unread-count',
  asyncHandler(residentUnreadNotificationCountHandler),
);
router.post('/notifications/read-all', asyncHandler(residentMarkAllNotificationsReadHandler));
router.get(
  '/notifications',
  validateQuery(listNotificationsQuerySchema),
  asyncHandler(residentListNotificationsHandler),
);
router.get(
  '/notifications/:notificationId',
  validateParams(notificationIdParamSchema),
  asyncHandler(residentGetNotificationHandler),
);
router.post(
  '/notifications/:notificationId/read',
  validateParams(notificationIdParamSchema),
  asyncHandler(residentMarkNotificationReadHandler),
);
router.post(
  '/notifications/:notificationId/unread',
  validateParams(notificationIdParamSchema),
  asyncHandler(residentMarkNotificationUnreadHandler),
);

export default router;
