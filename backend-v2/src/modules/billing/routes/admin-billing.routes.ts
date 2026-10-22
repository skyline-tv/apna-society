import { Router } from 'express';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  adjustBillHandler,
  billingSummaryHandler,
  billInterestHandler,
  cancelBillHandler,
  eligibleFlatsHandler,
  generateBillsHandler,
  getAdminReceiptHandler,
  getBillHandler,
  getPaymentHandler,
  listAdminReceiptsHandler,
  listBillsHandler,
  listPaymentsHandler,
  offlinePaymentHandler,
  refreshInterestHandler,
  refundPaymentHandler,
} from '../controllers/admin-billing.controller';
import {
  createAdditionalServiceHandler,
  deactivateAdditionalServiceHandler,
  getAdditionalServiceHandler,
  listAdditionalServicesHandler,
  updateAdditionalServiceHandler,
} from '../controllers/additional-service.controller';
import {
  adjustBillSchema,
  billIdParamSchema,
  billingSummaryQuerySchema,
  cancelBillSchema,
  generateBillsSchema,
  interestQuerySchema,
  listBillsQuerySchema,
  listPaymentsQuerySchema,
  listReceiptsQuerySchema,
  offlinePaymentSchema,
  paymentIdParamSchema,
  receiptIdParamSchema,
  refundPaymentSchema,
} from '../validators/billing.validators';
import {
  additionalServiceIdParamSchema,
  createAdditionalServiceSchema,
  deactivateAdditionalServiceSchema,
  listAdditionalServicesQuerySchema,
  updateAdditionalServiceSchema,
} from '../validators/additional-service.validators';

const router = Router();

router.post(
  '/billing/generate',
  validateBody(generateBillsSchema),
  asyncHandler(generateBillsHandler),
);
router.get('/billing/bills', validateQuery(listBillsQuerySchema), asyncHandler(listBillsHandler));
router.get(
  '/billing/bills/:billId',
  validateParams(billIdParamSchema),
  asyncHandler(getBillHandler),
);
router.get(
  '/billing/bills/:billId/interest',
  validateParams(billIdParamSchema),
  validateQuery(interestQuerySchema),
  asyncHandler(billInterestHandler),
);
router.post(
  '/billing/bills/:billId/adjust',
  validateParams(billIdParamSchema),
  validateBody(adjustBillSchema),
  asyncHandler(adjustBillHandler),
);
router.post(
  '/billing/bills/:billId/cancel',
  validateParams(billIdParamSchema),
  validateBody(cancelBillSchema),
  asyncHandler(cancelBillHandler),
);
router.get(
  '/billing/summary',
  validateQuery(billingSummaryQuerySchema),
  asyncHandler(billingSummaryHandler),
);
router.get('/billing/eligible-flats', asyncHandler(eligibleFlatsHandler));
router.post('/billing/interest/refresh', asyncHandler(refreshInterestHandler));

router.post(
  '/billing/additional-services',
  validateBody(createAdditionalServiceSchema),
  asyncHandler(createAdditionalServiceHandler),
);
router.get(
  '/billing/additional-services',
  validateQuery(listAdditionalServicesQuerySchema),
  asyncHandler(listAdditionalServicesHandler),
);
router.get(
  '/billing/additional-services/:serviceId',
  validateParams(additionalServiceIdParamSchema),
  asyncHandler(getAdditionalServiceHandler),
);
router.patch(
  '/billing/additional-services/:serviceId',
  validateParams(additionalServiceIdParamSchema),
  validateBody(updateAdditionalServiceSchema),
  asyncHandler(updateAdditionalServiceHandler),
);
router.post(
  '/billing/additional-services/:serviceId/deactivate',
  validateParams(additionalServiceIdParamSchema),
  validateBody(deactivateAdditionalServiceSchema),
  asyncHandler(deactivateAdditionalServiceHandler),
);

router.post(
  '/payments/offline',
  validateBody(offlinePaymentSchema),
  asyncHandler(offlinePaymentHandler),
);
router.get(
  '/payments',
  validateQuery(listPaymentsQuerySchema),
  asyncHandler(listPaymentsHandler),
);
router.get(
  '/payments/:paymentId',
  validateParams(paymentIdParamSchema),
  asyncHandler(getPaymentHandler),
);
router.post(
  '/payments/:paymentId/refund',
  validateParams(paymentIdParamSchema),
  validateBody(refundPaymentSchema),
  asyncHandler(refundPaymentHandler),
);

router.get(
  '/receipts',
  validateQuery(listReceiptsQuerySchema),
  asyncHandler(listAdminReceiptsHandler),
);
router.get(
  '/receipts/:receiptId',
  validateParams(receiptIdParamSchema),
  asyncHandler(getAdminReceiptHandler),
);

export default router;
