import { Router } from 'express';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  adjustChargeHandler,
  adminCollectionPaymentReceiptHandler,
  adminCollectionReceiptHandler,
  cancelCollectionHandler,
  closeCollectionHandler,
  collectionDashboardHandler,
  createCollectionHandler,
  exportCollectionChargesHandler,
  getCollectionHandler,
  listAdminCollectionPaymentsHandler,
  listChargeAdjustmentsHandler,
  listCollectionChargesHandler,
  listCollectionsHandler,
  offlineCollectionPaymentHandler,
  previewCollectionHandler,
  updateCollectionHandler,
} from '../controllers/admin-collection.controller';
import {
  adjustChargeSchema,
  cancelCollectionSchema,
  chargeIdParamSchema,
  collectionIdParamSchema,
  collectionPaymentIdParamSchema,
  collectionReceiptIdParamSchema,
  createCollectionSchema,
  listChargesQuerySchema,
  listCollectionPaymentsQuerySchema,
  listCollectionsQuerySchema,
  offlineCollectionPaymentSchema,
  previewCollectionSchema,
  updateCollectionSchema,
} from '../validators/collection.validators';

const router = Router();

router.post(
  '/collections/preview',
  validateBody(previewCollectionSchema),
  asyncHandler(previewCollectionHandler),
);
router.post(
  '/collections',
  validateBody(createCollectionSchema),
  asyncHandler(createCollectionHandler),
);
router.get(
  '/collections',
  validateQuery(listCollectionsQuerySchema),
  asyncHandler(listCollectionsHandler),
);
router.post(
  '/collections/payments/offline',
  validateBody(offlineCollectionPaymentSchema),
  asyncHandler(offlineCollectionPaymentHandler),
);
router.get(
  '/collections/receipts/:receiptId',
  validateParams(collectionReceiptIdParamSchema),
  asyncHandler(adminCollectionReceiptHandler),
);
router.get(
  '/collections/payments/:paymentId/receipt',
  validateParams(collectionPaymentIdParamSchema),
  asyncHandler(adminCollectionPaymentReceiptHandler),
);
router.post(
  '/collections/charges/:chargeId/adjust',
  validateParams(chargeIdParamSchema),
  validateBody(adjustChargeSchema),
  asyncHandler(adjustChargeHandler),
);
router.get(
  '/collections/charges/:chargeId/adjustments',
  validateParams(chargeIdParamSchema),
  asyncHandler(listChargeAdjustmentsHandler),
);
router.get(
  '/collections/:collectionId',
  validateParams(collectionIdParamSchema),
  asyncHandler(getCollectionHandler),
);
router.patch(
  '/collections/:collectionId',
  validateParams(collectionIdParamSchema),
  validateBody(updateCollectionSchema),
  asyncHandler(updateCollectionHandler),
);
router.post(
  '/collections/:collectionId/close',
  validateParams(collectionIdParamSchema),
  asyncHandler(closeCollectionHandler),
);
router.post(
  '/collections/:collectionId/cancel',
  validateParams(collectionIdParamSchema),
  validateBody(cancelCollectionSchema),
  asyncHandler(cancelCollectionHandler),
);
router.get(
  '/collections/:collectionId/dashboard',
  validateParams(collectionIdParamSchema),
  asyncHandler(collectionDashboardHandler),
);
router.get(
  '/collections/:collectionId/charges',
  validateParams(collectionIdParamSchema),
  validateQuery(listChargesQuerySchema),
  asyncHandler(listCollectionChargesHandler),
);
router.get(
  '/collections/:collectionId/charges.csv',
  validateParams(collectionIdParamSchema),
  asyncHandler(exportCollectionChargesHandler),
);
router.get(
  '/collections/:collectionId/payments',
  validateParams(collectionIdParamSchema),
  validateQuery(listCollectionPaymentsQuerySchema),
  asyncHandler(listAdminCollectionPaymentsHandler),
);

export default router;
