import { Router } from 'express';
import { resolveResidentSociety } from '../../../middleware/resident-society';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  residentApproveHandler,
  residentAuthorizeParcelHandler,
  residentCancelHandler,
  residentCollectParcelHandler,
  residentGetParcelHandler,
  residentGetVisitorHandler,
  residentListParcelsHandler,
  residentListVisitorsHandler,
  residentPendingVisitorsHandler,
  residentRejectHandler,
} from '../controllers/visitor.controller';
import {
  listParcelsQuerySchema,
  listVisitorsQuerySchema,
  parcelIdParamSchema,
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
router.post(
  '/visitors/:visitorId/leave-parcel',
  validateParams(visitorIdParamSchema),
  asyncHandler(residentAuthorizeParcelHandler),
);

router.get(
  '/parcels',
  validateQuery(listParcelsQuerySchema),
  asyncHandler(residentListParcelsHandler),
);
router.get(
  '/parcels/:parcelId',
  validateParams(parcelIdParamSchema),
  asyncHandler(residentGetParcelHandler),
);
router.post(
  '/parcels/:parcelId/collect',
  validateParams(parcelIdParamSchema),
  asyncHandler(residentCollectParcelHandler),
);

export default router;
