import { Router } from 'express';
import { authenticate } from '../../../middleware/authenticate';
import { requireRoles } from '../../../middleware/authorize';
import { resolveGuardSociety } from '../../../middleware/guard-society';
import { visitorOtpRateLimiter } from '../../../middleware/rate-limit';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  guardCancelParcelHandler,
  guardCheckoutHandler,
  guardCreateVisitorHandler,
  guardDashboardHandler,
  guardConfirmEntryHandler,
  guardDeliverParcelHandler,
  guardGetParcelHandler,
  guardGetVisitorHandler,
  guardListParcelsHandler,
  guardListVisitorsHandler,
  guardReceiveParcelHandler,
  guardVerifyOtpByCodeHandler,
  guardVerifyOtpHandler,
} from '../controllers/visitor.controller';
import {
  cancelParcelSchema,
  createVisitorSchema,
  listParcelsQuerySchema,
  listVisitorsQuerySchema,
  parcelIdParamSchema,
  verifyEntryOtpSchema,
  visitorIdParamSchema,
} from '../validators/visitor.validators';
import guardVehicleRoutes from '../../vehicles/routes/guard-vehicle.routes';

const router = Router();

router.use(authenticate, requireRoles('GUARD'), (req, res, next) => {
  void resolveGuardSociety(req, res, next);
});

router.get('/dashboard', asyncHandler(guardDashboardHandler));
router.post('/visitors', validateBody(createVisitorSchema), asyncHandler(guardCreateVisitorHandler));
router.get(
  '/visitors',
  validateQuery(listVisitorsQuerySchema),
  asyncHandler(guardListVisitorsHandler),
);
router.post(
  '/visitors/verify-entry-otp',
  visitorOtpRateLimiter,
  validateBody(verifyEntryOtpSchema),
  asyncHandler(guardVerifyOtpByCodeHandler),
);
router.get(
  '/visitors/:visitorId',
  validateParams(visitorIdParamSchema),
  asyncHandler(guardGetVisitorHandler),
);
router.post(
  '/visitors/:visitorId/verify-entry-otp',
  visitorOtpRateLimiter,
  validateParams(visitorIdParamSchema),
  validateBody(verifyEntryOtpSchema),
  asyncHandler(guardVerifyOtpHandler),
);
router.post(
  '/visitors/:visitorId/confirm-entry',
  validateParams(visitorIdParamSchema),
  asyncHandler(guardConfirmEntryHandler),
);
router.post(
  '/visitors/:visitorId/checkout',
  validateParams(visitorIdParamSchema),
  asyncHandler(guardCheckoutHandler),
);

router.get(
  '/parcels',
  validateQuery(listParcelsQuerySchema),
  asyncHandler(guardListParcelsHandler),
);
router.get(
  '/parcels/:parcelId',
  validateParams(parcelIdParamSchema),
  asyncHandler(guardGetParcelHandler),
);
router.post(
  '/parcels/:parcelId/receive',
  validateParams(parcelIdParamSchema),
  asyncHandler(guardReceiveParcelHandler),
);
router.post(
  '/parcels/:parcelId/deliver',
  validateParams(parcelIdParamSchema),
  asyncHandler(guardDeliverParcelHandler),
);
router.post(
  '/parcels/:parcelId/cancel',
  validateParams(parcelIdParamSchema),
  validateBody(cancelParcelSchema),
  asyncHandler(guardCancelParcelHandler),
);

router.use(guardVehicleRoutes);

export default router;
