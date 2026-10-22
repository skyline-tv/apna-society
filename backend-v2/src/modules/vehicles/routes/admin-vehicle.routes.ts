import { Router } from 'express';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  adminAllocateHandler,
  adminCreateSlotHandler,
  adminGetAllocationHandler,
  adminGetSlotHandler,
  adminListAllocationsHandler,
  adminListSlotsHandler,
  adminParkingSummaryHandler,
  adminReleaseAllocationHandler,
  adminSetSlotActiveHandler,
  adminUpdateSlotHandler,
} from '../controllers/parking.controller';
import {
  adminDeactivateVehicleHandler,
  adminListVehiclesHandler,
  adminRegisterVehicleHandler,
  adminUpdateVehicleHandler,
} from '../controllers/vehicle.controller';
import {
  adminRegisterVehicleSchema,
  adminUpdateVehicleSchema,
  allocateParkingSchema,
  allocationIdParamSchema,
  createParkingSlotSchema,
  deactivateVehicleSchema,
  listAdminVehiclesQuerySchema,
  listAllocationsQuerySchema,
  listParkingSlotsQuerySchema,
  releaseAllocationSchema,
  setParkingSlotActiveSchema,
  slotIdParamSchema,
  updateParkingSlotSchema,
  vehicleIdParamSchema,
} from '../validators/vehicle.validators';

const router = Router();

router.get(
  '/vehicles',
  validateQuery(listAdminVehiclesQuerySchema),
  asyncHandler(adminListVehiclesHandler),
);
router.post(
  '/vehicles',
  validateBody(adminRegisterVehicleSchema),
  asyncHandler(adminRegisterVehicleHandler),
);
router.patch(
  '/vehicles/:vehicleId',
  validateParams(vehicleIdParamSchema),
  validateBody(adminUpdateVehicleSchema),
  asyncHandler(adminUpdateVehicleHandler),
);
router.post(
  '/vehicles/:vehicleId/deactivate',
  validateParams(vehicleIdParamSchema),
  validateBody(deactivateVehicleSchema),
  asyncHandler(adminDeactivateVehicleHandler),
);

router.post(
  '/parking/slots',
  validateBody(createParkingSlotSchema),
  asyncHandler(adminCreateSlotHandler),
);
router.get(
  '/parking/slots',
  validateQuery(listParkingSlotsQuerySchema),
  asyncHandler(adminListSlotsHandler),
);
router.get('/parking/summary', asyncHandler(adminParkingSummaryHandler));
router.get(
  '/parking/slots/:slotId',
  validateParams(slotIdParamSchema),
  asyncHandler(adminGetSlotHandler),
);
router.patch(
  '/parking/slots/:slotId',
  validateParams(slotIdParamSchema),
  validateBody(updateParkingSlotSchema),
  asyncHandler(adminUpdateSlotHandler),
);
router.post(
  '/parking/slots/:slotId/set-active',
  validateParams(slotIdParamSchema),
  validateBody(setParkingSlotActiveSchema),
  asyncHandler(adminSetSlotActiveHandler),
);

router.post(
  '/parking/allocations',
  validateBody(allocateParkingSchema),
  asyncHandler(adminAllocateHandler),
);
router.get(
  '/parking/allocations',
  validateQuery(listAllocationsQuerySchema),
  asyncHandler(adminListAllocationsHandler),
);
router.get(
  '/parking/allocations/:allocationId',
  validateParams(allocationIdParamSchema),
  asyncHandler(adminGetAllocationHandler),
);
router.post(
  '/parking/allocations/:allocationId/release',
  validateParams(allocationIdParamSchema),
  validateBody(releaseAllocationSchema),
  asyncHandler(adminReleaseAllocationHandler),
);

export default router;
