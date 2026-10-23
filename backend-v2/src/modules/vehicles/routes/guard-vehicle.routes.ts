import { Router } from 'express';
import { validateBody, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  guardListVehicleLogsHandler,
  guardVehicleEntryHandler,
  guardVehicleExitHandler,
  guardVehicleLookupHandler,
} from '../controllers/vehicle-log.controller';
import {
  listVehicleLogsQuerySchema,
  vehicleEntrySchema,
  vehicleExitSchema,
  vehicleLookupQuerySchema,
} from '../validators/vehicle.validators';

/**
 * Mounted under the authenticated guard router (society already resolved).
 */
const router = Router();

router.get(
  '/vehicles/lookup',
  validateQuery(vehicleLookupQuerySchema),
  asyncHandler(guardVehicleLookupHandler),
);
router.post(
  '/vehicles/entry',
  validateBody(vehicleEntrySchema),
  asyncHandler(guardVehicleEntryHandler),
);
router.post(
  '/vehicles/exit',
  validateBody(vehicleExitSchema),
  asyncHandler(guardVehicleExitHandler),
);
router.get(
  '/vehicles/logs',
  validateQuery(listVehicleLogsQuerySchema),
  asyncHandler(guardListVehicleLogsHandler),
);

export default router;
