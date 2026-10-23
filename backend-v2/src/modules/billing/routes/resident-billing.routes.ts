import { Router } from 'express';
import { resolveResidentSociety } from '../../../middleware/resident-society';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { forbidden } from '../../../shared/errors/app-error';
import { asyncHandler } from '../../../utils/async-handler';
import {
  completeDemoPaymentHandler,
  createPaymentOrderHandler,
  residentBillInterestHandler,
  residentGetBillHandler,
  residentGetReceiptHandler,
  residentListBillsHandler,
  residentListPaymentsHandler,
  residentListReceiptsHandler,
  residentPaymentReceiptHandler,
  verifyPaymentHandler,
} from '../controllers/resident-billing.controller';
import {
  billIdParamSchema,
  completeDemoPaymentSchema,
  interestQuerySchema,
  listBillsQuerySchema,
  listPaymentsQuerySchema,
  listReceiptsQuerySchema,
  paymentIdParamSchema,
  receiptIdParamSchema,
  verifyPaymentSchema,
} from '../validators/billing.validators';

const router = Router();

router.use(resolveResidentSociety);
// Scope financial denial to billing paths only — this router is mounted at /resident
// and must not block visitor/occupancy routes on the parent router.
router.use('/billing', (req, _res, next) => {
  const roles = req.user?.roles ?? [];
  if (roles.includes('TENANT') && !roles.includes('OWNER') && !roles.includes('ADMIN')) {
    next(forbidden('Tenants cannot access billing APIs', 'TENANT_BILLING_DENIED'));
    return;
  }
  if (roles.includes('GUARD') && !roles.includes('OWNER') && !roles.includes('ADMIN')) {
    next(forbidden('Guards cannot access billing APIs', 'GUARD_BILLING_DENIED'));
    return;
  }
  next();
});

router.get(
  '/billing/bills',
  validateQuery(listBillsQuerySchema),
  asyncHandler(residentListBillsHandler),
);
router.get(
  '/billing/bills/:billId',
  validateParams(billIdParamSchema),
  asyncHandler(residentGetBillHandler),
);
router.get(
  '/billing/bills/:billId/interest',
  validateParams(billIdParamSchema),
  validateQuery(interestQuerySchema),
  asyncHandler(residentBillInterestHandler),
);
router.post(
  '/billing/bills/:billId/payment-order',
  validateParams(billIdParamSchema),
  asyncHandler(createPaymentOrderHandler),
);
router.post(
  '/billing/verify-payment',
  validateBody(verifyPaymentSchema),
  asyncHandler(verifyPaymentHandler),
);
router.post(
  '/billing/demo-complete',
  validateBody(completeDemoPaymentSchema),
  asyncHandler(completeDemoPaymentHandler),
);
router.get(
  '/billing/payments',
  validateQuery(listPaymentsQuerySchema),
  asyncHandler(residentListPaymentsHandler),
);
router.get(
  '/billing/payments/:paymentId/receipt',
  validateParams(paymentIdParamSchema),
  asyncHandler(residentPaymentReceiptHandler),
);
router.get(
  '/billing/receipts',
  validateQuery(listReceiptsQuerySchema),
  asyncHandler(residentListReceiptsHandler),
);
router.get(
  '/billing/receipts/:receiptId',
  validateParams(receiptIdParamSchema),
  asyncHandler(residentGetReceiptHandler),
);

export default router;
