import { Router } from 'express';
import { resolveResidentSociety } from '../../../middleware/resident-society';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  residentAvailabilityHandler,
  residentCancelBookingHandler,
  residentCreateBookingHandler,
  residentGetBookingHandler,
  residentGetFacilityHandler,
  residentListBookingsHandler,
  residentListFacilitiesHandler,
} from '../controllers/facility.controller';
import {
  availabilityQuerySchema,
  bookingIdParamSchema,
  cancelBookingSchema,
  createBookingSchema,
  facilityIdParamSchema,
  listBookingsQuerySchema,
  listFacilitiesQuerySchema,
} from '../validators/facility.validators';

const router = Router();

router.use(resolveResidentSociety);

router.get(
  '/facilities',
  validateQuery(listFacilitiesQuerySchema),
  asyncHandler(residentListFacilitiesHandler),
);
router.get(
  '/facilities/:facilityId',
  validateParams(facilityIdParamSchema),
  asyncHandler(residentGetFacilityHandler),
);
router.get(
  '/facilities/:facilityId/availability',
  validateParams(facilityIdParamSchema),
  validateQuery(availabilityQuerySchema),
  asyncHandler(residentAvailabilityHandler),
);
router.post(
  '/facilities/:facilityId/bookings',
  validateParams(facilityIdParamSchema),
  validateBody(createBookingSchema),
  asyncHandler(residentCreateBookingHandler),
);
router.get(
  '/facility-bookings',
  validateQuery(listBookingsQuerySchema),
  asyncHandler(residentListBookingsHandler),
);
router.get(
  '/facility-bookings/:bookingId',
  validateParams(bookingIdParamSchema),
  asyncHandler(residentGetBookingHandler),
);
router.post(
  '/facility-bookings/:bookingId/cancel',
  validateParams(bookingIdParamSchema),
  validateBody(cancelBookingSchema),
  asyncHandler(residentCancelBookingHandler),
);

export default router;
