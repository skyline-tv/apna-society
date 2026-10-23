import { Router } from 'express';
import { resolveResidentSociety } from '../../../middleware/resident-society';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { forbidden } from '../../../shared/errors/app-error';
import { asyncHandler } from '../../../utils/async-handler';
import {
  residentCollectionPaymentReceiptHandler,
  residentCollectionReceiptHandler,
  residentCreatePaymentOrderHandler,
  residentDemoCollectionPaymentHandler,
  residentGetChargeHandler,
  residentListCollectionPaymentsHandler,
  residentListCollectionsHandler,
  residentVerifyCollectionPaymentHandler,
} from '../controllers/resident-collection.controller';
import {
  chargeIdParamSchema,
  collectionPaymentIdParamSchema,
  collectionReceiptIdParamSchema,
  completeCollectionDemoSchema,
  createCollectionPaymentOrderSchema,
  listCollectionPaymentsQuerySchema,
  verifyCollectionPaymentSchema,
} from '../validators/collection.validators';

const router = Router();

router.use(resolveResidentSociety);
router.use('/collections', (req, _res, next) => {
  const roles = req.user?.roles ?? [];
  if (roles.includes('TENANT') && !roles.includes('OWNER') && !roles.includes('ADMIN')) {
    next(forbidden('Tenants cannot access collection APIs', 'TENANT_BILLING_DENIED'));
    return;
  }
  if (roles.includes('GUARD') && !roles.includes('OWNER') && !roles.includes('ADMIN')) {
    next(forbidden('Guards cannot access collection APIs', 'GUARD_BILLING_DENIED'));
    return;
  }
  next();
});

router.get('/collections', asyncHandler(residentListCollectionsHandler));
router.get(
  '/collections/charges/:chargeId',
  validateParams(chargeIdParamSchema),
  asyncHandler(residentGetChargeHandler),
);
router.post(
  '/collections/charges/:chargeId/payment-order',
  validateParams(chargeIdParamSchema),
  validateBody(createCollectionPaymentOrderSchema),
  asyncHandler(residentCreatePaymentOrderHandler),
);
router.post(
  '/collections/verify-payment',
  validateBody(verifyCollectionPaymentSchema),
  asyncHandler(residentVerifyCollectionPaymentHandler),
);
router.post(
  '/collections/demo-complete',
  validateBody(completeCollectionDemoSchema),
  asyncHandler(residentDemoCollectionPaymentHandler),
);
router.get(
  '/collections/payments',
  validateQuery(listCollectionPaymentsQuerySchema),
  asyncHandler(residentListCollectionPaymentsHandler),
);
router.get(
  '/collections/receipts/:receiptId',
  validateParams(collectionReceiptIdParamSchema),
  asyncHandler(residentCollectionReceiptHandler),
);
router.get(
  '/collections/payments/:paymentId/receipt',
  validateParams(collectionPaymentIdParamSchema),
  asyncHandler(residentCollectionPaymentReceiptHandler),
);

export default router;
