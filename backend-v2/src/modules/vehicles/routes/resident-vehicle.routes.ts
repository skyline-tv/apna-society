import { Router } from 'express';
import { resolveResidentSociety } from '../../../middleware/resident-society';
import { validateBody, validateParams } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  residentGetParkingAllocationHandler,
  residentListParkingHandler,
} from '../controllers/parking.controller';
import {
  residentDeactivateVehicleHandler,
  residentGetVehicleHandler,
  residentListVehiclesHandler,
  residentRegisterVehicleHandler,
  residentUpdateVehicleHandler,
} from '../controllers/vehicle.controller';
import {
  allocationIdParamSchema,
  deactivateVehicleSchema,
  registerVehicleSchema,
  updateVehicleSchema,
  vehicleIdParamSchema,
} from '../validators/vehicle.validators';

const router = Router();

router.use(resolveResidentSociety);

router.post(
  '/vehicles',
  validateBody(registerVehicleSchema),
  asyncHandler(residentRegisterVehicleHandler),
);
router.get('/vehicles', asyncHandler(residentListVehiclesHandler));
router.get(
  '/vehicles/:vehicleId',
  validateParams(vehicleIdParamSchema),
  asyncHandler(residentGetVehicleHandler),
);
router.patch(
  '/vehicles/:vehicleId',
  validateParams(vehicleIdParamSchema),
  validateBody(updateVehicleSchema),
  asyncHandler(residentUpdateVehicleHandler),
);
router.post(
  '/vehicles/:vehicleId/deactivate',
  validateParams(vehicleIdParamSchema),
  validateBody(deactivateVehicleSchema),
  asyncHandler(residentDeactivateVehicleHandler),
);

router.get('/parking', asyncHandler(residentListParkingHandler));
router.get(
  '/parking/allocations/:allocationId',
  validateParams(allocationIdParamSchema),
  asyncHandler(residentGetParkingAllocationHandler),
);

export default router;
