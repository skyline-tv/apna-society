import { Router } from 'express';
import { resolveAdminSociety } from '../../../middleware/admin-society';
import { authenticate } from '../../../middleware/authenticate';
import { requireRoles } from '../../../middleware/authorize';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  deactivateUserHandler,
  getUserHandler,
  listUsersHandler,
  patchUserHandler,
  provisionUserHandler,
} from '../../users/controllers/admin-user.controller';
import {
  deactivateUserSchema,
  listUsersQuerySchema,
  provisionUserSchema,
  updateUserSchema,
  userIdParamSchema,
} from '../../users/validators/admin-user.validators';
import {
  assignOwnerHandler,
  assignTenantHandler,
  createFlatHandler,
  createWingHandler,
  endOwnerOccupancyHandler,
  endTenantOccupancyHandler,
  getDashboardHandler,
  getFlatHandler,
  getSocietyConfigurationHandler,
  getSocietyHandler,
  getWingHandler,
  listFlatResidentsHandler,
  listFlatsHandler,
  listOccupanciesHandler,
  listWingsHandler,
  occupancyHistoryHandler,
  patchFlatHandler,
  patchSocietyHandler,
  patchWingHandler,
} from '../controllers/admin.controller';
import {
  createFlatSchema,
  createWingSchema,
  flatIdParamSchema,
  listFlatsQuerySchema,
  updateFlatSchema,
  updateSocietySchema,
  updateWingSchema,
  wingIdParamSchema,
} from '../validators/admin.validators';
import {
  assignOccupancySchema,
  endOccupancySchema,
  listOccupanciesQuerySchema,
  occupancyHistoryQuerySchema,
} from '../validators/occupancy.validators';
import adminAnnouncementRoutes from '../../announcements/routes/admin-announcement.routes';
import adminBillingRoutes from '../../billing/routes/admin-billing.routes';
import adminComplaintRoutes from '../../complaints/routes/admin-complaint.routes';
import adminFacilityRoutes from '../../facilities/routes/admin-facility.routes';
import adminReportRoutes from '../../reports/routes/admin-report.routes';
import adminStaffRoutes from '../../staff/routes/admin-staff.routes';
import adminVehicleRoutes from '../../vehicles/routes/admin-vehicle.routes';
import adminVisitorRoutes from '../../visitors/routes/admin-visitor.routes';
import { opsMetricsHandler } from '../../ops/metrics.controller';

const router = Router();

router.use(authenticate, requireRoles('ADMIN'), (req, res, next) => {
  void resolveAdminSociety(req, res, next);
});

router.use(adminBillingRoutes);
router.use(adminVisitorRoutes);
router.use(adminVehicleRoutes);
router.use(adminComplaintRoutes);
router.use(adminStaffRoutes);
router.use(adminFacilityRoutes);
router.use(adminAnnouncementRoutes);
router.use(adminReportRoutes);

router.get('/society', asyncHandler(getSocietyHandler));
router.patch('/society', validateBody(updateSocietySchema), asyncHandler(patchSocietyHandler));
router.get('/society/configuration', asyncHandler(getSocietyConfigurationHandler));

router.get('/wings', asyncHandler(listWingsHandler));
router.post('/wings', validateBody(createWingSchema), asyncHandler(createWingHandler));
router.get('/wings/:wingId', validateParams(wingIdParamSchema), asyncHandler(getWingHandler));
router.patch(
  '/wings/:wingId',
  validateParams(wingIdParamSchema),
  validateBody(updateWingSchema),
  asyncHandler(patchWingHandler),
);

router.get('/flats', validateQuery(listFlatsQuerySchema), asyncHandler(listFlatsHandler));
router.post('/flats', validateBody(createFlatSchema), asyncHandler(createFlatHandler));
router.get('/flats/:flatId', validateParams(flatIdParamSchema), asyncHandler(getFlatHandler));
router.patch(
  '/flats/:flatId',
  validateParams(flatIdParamSchema),
  validateBody(updateFlatSchema),
  asyncHandler(patchFlatHandler),
);
router.get(
  '/flats/:flatId/residents',
  validateParams(flatIdParamSchema),
  asyncHandler(listFlatResidentsHandler),
);

router.post(
  '/flats/:flatId/assign-owner',
  validateParams(flatIdParamSchema),
  validateBody(assignOccupancySchema),
  asyncHandler(assignOwnerHandler),
);
router.post(
  '/flats/:flatId/assign-tenant',
  validateParams(flatIdParamSchema),
  validateBody(assignOccupancySchema),
  asyncHandler(assignTenantHandler),
);
router.post(
  '/flats/:flatId/end-owner-occupancy',
  validateParams(flatIdParamSchema),
  validateBody(endOccupancySchema),
  asyncHandler(endOwnerOccupancyHandler),
);
router.post(
  '/flats/:flatId/end-tenant-occupancy',
  validateParams(flatIdParamSchema),
  validateBody(endOccupancySchema),
  asyncHandler(endTenantOccupancyHandler),
);
router.get(
  '/flats/:flatId/occupancy-history',
  validateParams(flatIdParamSchema),
  validateQuery(occupancyHistoryQuerySchema),
  asyncHandler(occupancyHistoryHandler),
);

router.get(
  '/occupancies',
  validateQuery(listOccupanciesQuerySchema),
  asyncHandler(listOccupanciesHandler),
);

router.get('/users', validateQuery(listUsersQuerySchema), asyncHandler(listUsersHandler));
router.post('/users', validateBody(provisionUserSchema), asyncHandler(provisionUserHandler));
router.get('/users/:userId', validateParams(userIdParamSchema), asyncHandler(getUserHandler));
router.patch(
  '/users/:userId',
  validateParams(userIdParamSchema),
  validateBody(updateUserSchema),
  asyncHandler(patchUserHandler),
);
router.post(
  '/users/:userId/deactivate',
  validateParams(userIdParamSchema),
  validateBody(deactivateUserSchema),
  asyncHandler(deactivateUserHandler),
);

router.get('/dashboard', asyncHandler(getDashboardHandler));
router.get('/ops/metrics', asyncHandler(opsMetricsHandler));

export default router;
