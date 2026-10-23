import { Router } from 'express';
import { authenticate } from '../../../middleware/authenticate';
import { requireResidentPushAccess } from '../../../middleware/authorize';
import { resolveMemberSociety } from '../../../middleware/member-society';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  listNotificationsQuerySchema,
  notificationIdParamSchema,
} from '../../announcements/validators/announcement.validators';
import {
  residentGetNotificationHandler,
  residentListNotificationsHandler,
  residentMarkAllNotificationsReadHandler,
  residentMarkNotificationReadHandler,
  residentMarkNotificationUnreadHandler,
  residentUnreadNotificationCountHandler,
} from '../controllers/notification.controller';
import {
  registerDeviceTokenHandler,
  unregisterDeviceTokenHandler,
} from '../controllers/device-token.controller';
import {
  registerDeviceTokenSchema,
  unregisterDeviceTokenSchema,
} from '../validators/device-token.validators';

const router = Router();

router.use(authenticate, (req, res, next) => {
  void resolveMemberSociety(req, res, next);
});

router.post(
  '/device-tokens',
  requireResidentPushAccess,
  validateBody(registerDeviceTokenSchema),
  asyncHandler(registerDeviceTokenHandler),
);
router.delete(
  '/device-tokens',
  requireResidentPushAccess,
  validateBody(unregisterDeviceTokenSchema),
  asyncHandler(unregisterDeviceTokenHandler),
);

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
