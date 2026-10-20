import { Router } from 'express';
import { resolveResidentSociety } from '../../../middleware/resident-society';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  residentApproveHandler,
  residentCancelHandler,
  residentGetVisitorHandler,
  residentListVisitorsHandler,
  residentPendingVisitorsHandler,
  residentRejectHandler,
} from '../controllers/visitor.controller';
import {
  listVisitorsQuerySchema,
  rejectVisitorSchema,
  visitorIdParamSchema,
} from '../validators/visitor.validators';

const router = Router();

router.use(resolveResidentSociety);

router.get(
  '/visitors',
  validateQuery(listVisitorsQuerySchema),
  asyncHandler(residentListVisitorsHandler),
);
router.get('/visitors/pending', asyncHandler(residentPendingVisitorsHandler));
router.get(
  '/visitors/:visitorId',
  validateParams(visitorIdParamSchema),
  asyncHandler(residentGetVisitorHandler),
);
router.post(
  '/visitors/:visitorId/approve',
  validateParams(visitorIdParamSchema),
  asyncHandler(residentApproveHandler),
);
router.post(
  '/visitors/:visitorId/reject',
  validateParams(visitorIdParamSchema),
  validateBody(rejectVisitorSchema),
  asyncHandler(residentRejectHandler),
);
router.post(
  '/visitors/:visitorId/cancel',
  validateParams(visitorIdParamSchema),
  asyncHandler(residentCancelHandler),
);

export default router;
