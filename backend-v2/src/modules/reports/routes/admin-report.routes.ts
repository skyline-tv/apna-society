import { Router } from 'express';
import { validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  collectionReportHandler,
  complaintAnalyticsHandler,
  exportReportHandler,
  financialReportHandler,
  outstandingReportHandler,
  reportsDashboardHandler,
} from '../controllers/report.controller';
import {
  collectionReportQuerySchema,
  complaintAnalyticsQuerySchema,
  dashboardReportQuerySchema,
  exportQuerySchema,
  exportTypeParamSchema,
  financialReportQuerySchema,
  outstandingReportQuerySchema,
} from '../validators/report.validators';

const router = Router();

router.get(
  '/reports/dashboard',
  validateQuery(dashboardReportQuerySchema),
  asyncHandler(reportsDashboardHandler),
);
router.get(
  '/reports/financial',
  validateQuery(financialReportQuerySchema),
  asyncHandler(financialReportHandler),
);
router.get(
  '/reports/collections',
  validateQuery(collectionReportQuerySchema),
  asyncHandler(collectionReportHandler),
);
router.get(
  '/reports/outstanding',
  validateQuery(outstandingReportQuerySchema),
  asyncHandler(outstandingReportHandler),
);
router.get(
  '/reports/complaints',
  validateQuery(complaintAnalyticsQuerySchema),
  asyncHandler(complaintAnalyticsHandler),
);
router.get(
  '/reports/export/:type',
  validateParams(exportTypeParamSchema),
  validateQuery(exportQuerySchema),
  asyncHandler(exportReportHandler),
);

export default router;
