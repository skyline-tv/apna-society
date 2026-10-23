import { Router } from 'express';
import { authenticate } from '../../../middleware/authenticate';
import { requireRoles } from '../../../middleware/authorize';
import { validateParams } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import { flatIdParamSchema } from '../../society/validators/admin.validators';
import {
  residentFlatHandler,
  residentFlatsHandler,
  residentOccupancyHandler,
  residentProfileHandler,
} from '../controllers/resident.controller';
import residentAnnouncementRoutes from '../../announcements/routes/resident-announcement.routes';
import residentBillingRoutes from '../../billing/routes/resident-billing.routes';
import residentCollectionRoutes from '../../collections/routes/resident-collection.routes';
import residentComplaintRoutes from '../../complaints/routes/resident-complaint.routes';
import residentFacilityRoutes from '../../facilities/routes/resident-facility.routes';
import residentNotificationRoutes from '../../notifications/routes/resident-notification.routes';
import residentVehicleRoutes from '../../vehicles/routes/resident-vehicle.routes';
import residentVisitorRoutes from '../../visitors/routes/resident-visitor.routes';

const router = Router();

router.use(authenticate, requireRoles('OWNER', 'TENANT', 'ADMIN'));

router.get('/profile', asyncHandler(residentProfileHandler));
router.get('/flats', asyncHandler(residentFlatsHandler));
router.get('/flats/:flatId', validateParams(flatIdParamSchema), asyncHandler(residentFlatHandler));
router.get(
  '/flats/:flatId/occupancy',
  validateParams(flatIdParamSchema),
  asyncHandler(residentOccupancyHandler),
);

router.use(residentBillingRoutes);
router.use(residentCollectionRoutes);
router.use(residentVisitorRoutes);
router.use(residentVehicleRoutes);
router.use(residentComplaintRoutes);
router.use(residentFacilityRoutes);
router.use(residentAnnouncementRoutes);
router.use(residentNotificationRoutes);

export default router;
