import { Router } from 'express';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  adminApproveBookingHandler,
  adminCancelBookingHandler,
  adminCreateFacilityHandler,
  adminFacilitySummaryHandler,
  adminGetBookingHandler,
  adminGetFacilityHandler,
  adminListBookingsHandler,
  adminListFacilitiesHandler,
  adminRejectBookingHandler,
  adminSetFacilityActiveHandler,
  adminUpdateFacilityHandler,
} from '../controllers/facility.controller';
import {
  approveBookingSchema,
  bookingIdParamSchema,
  cancelBookingSchema,
  createFacilitySchema,
  facilityIdParamSchema,
  listBookingsQuerySchema,
  listFacilitiesQuerySchema,
  rejectBookingSchema,
  setFacilityActiveSchema,
  updateFacilitySchema,
} from '../validators/facility.validators';

const router = Router();

router.post('/facilities', validateBody(createFacilitySchema), asyncHandler(adminCreateFacilityHandler));
router.get(
  '/facilities',
  validateQuery(listFacilitiesQuerySchema),
  asyncHandler(adminListFacilitiesHandler),
);
router.get('/facilities/summary', asyncHandler(adminFacilitySummaryHandler));
router.get(
  '/facilities/:facilityId',
  validateParams(facilityIdParamSchema),
  asyncHandler(adminGetFacilityHandler),
);
router.patch(
  '/facilities/:facilityId',
  validateParams(facilityIdParamSchema),
  validateBody(updateFacilitySchema),
  asyncHandler(adminUpdateFacilityHandler),
);
router.post(
  '/facilities/:facilityId/set-active',
  validateParams(facilityIdParamSchema),
  validateBody(setFacilityActiveSchema),
  asyncHandler(adminSetFacilityActiveHandler),
);

router.get(
  '/facility-bookings',
  validateQuery(listBookingsQuerySchema),
  asyncHandler(adminListBookingsHandler),
);
router.get(
  '/facility-bookings/summary',
  asyncHandler(adminFacilitySummaryHandler),
);
router.get(
  '/facility-bookings/:bookingId',
  validateParams(bookingIdParamSchema),
  asyncHandler(adminGetBookingHandler),
);
router.post(
  '/facility-bookings/:bookingId/approve',
  validateParams(bookingIdParamSchema),
  validateBody(approveBookingSchema),
  asyncHandler(adminApproveBookingHandler),
);
router.post(
  '/facility-bookings/:bookingId/reject',
  validateParams(bookingIdParamSchema),
  validateBody(rejectBookingSchema),
  asyncHandler(adminRejectBookingHandler),
);
router.post(
  '/facility-bookings/:bookingId/cancel',
  validateParams(bookingIdParamSchema),
  validateBody(cancelBookingSchema),
  asyncHandler(adminCancelBookingHandler),
);

export default router;
