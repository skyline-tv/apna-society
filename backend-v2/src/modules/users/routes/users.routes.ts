import { Router } from 'express';
import { authenticate } from '../../../middleware/authenticate';
import { requireRoles } from '../../../middleware/authorize';
import { asyncHandler } from '../../../utils/async-handler';
import { listUsersHandler } from '../controllers/user.controller';

/**
 * Admin-only user listing foundation. Provisioning endpoints arrive later.
 * Public registration is intentionally not exposed.
 */
const router = Router();

router.get('/', authenticate, requireRoles('ADMIN'), asyncHandler(listUsersHandler));

export default router;
