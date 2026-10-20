import { Router } from 'express';
import { validateBody, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  guardListVehicleLogsHandler,
  guardVehicleEntryHandler,
  guardVehicleExitHandler,
} from '../controllers/vehicle-log.controller';
import {
  listVehicleLogsQuerySchema,
  vehicleEntrySchema,
  vehicleExitSchema,
} from '../validators/vehicle.validators';

/**
 * Mounted under the authenticated guard router (society already resolved).
 */
const router = Router();

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
