import { Router } from 'express';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  deactivateGuardHandler,
  getGuardHandler,
  listGuardsHandler,
  patchGuardHandler,
  provisionGuardHandler,
} from '../controllers/admin-guard.controller';
import {
  adminGetVisitorHandler,
  adminListVisitorsHandler,
  adminVisitorSummaryHandler,
} from '../controllers/visitor.controller';
import {
  deactivateGuardSchema,
  guardIdParamSchema,
  listGuardsQuerySchema,
  listVisitorsQuerySchema,
  provisionGuardSchema,
  updateGuardSchema,
  visitorIdParamSchema,
} from '../validators/visitor.validators';

const router = Router();

router.post('/guards', validateBody(provisionGuardSchema), asyncHandler(provisionGuardHandler));
router.get('/guards', validateQuery(listGuardsQuerySchema), asyncHandler(listGuardsHandler));
router.get('/guards/:guardId', validateParams(guardIdParamSchema), asyncHandler(getGuardHandler));
router.patch(
  '/guards/:guardId',
  validateParams(guardIdParamSchema),
  validateBody(updateGuardSchema),
  asyncHandler(patchGuardHandler),
);
router.post(
  '/guards/:guardId/deactivate',
  validateParams(guardIdParamSchema),
  validateBody(deactivateGuardSchema),
  asyncHandler(deactivateGuardHandler),
);

router.get(
  '/visitors',
  validateQuery(listVisitorsQuerySchema),
  asyncHandler(adminListVisitorsHandler),
);
router.get('/visitors/summary', asyncHandler(adminVisitorSummaryHandler));
router.get(
  '/visitors/:visitorId',
  validateParams(visitorIdParamSchema),
  asyncHandler(adminGetVisitorHandler),
);

export default router;
