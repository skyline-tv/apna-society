import { Router } from 'express';
import { authenticate } from '../../../middleware/authenticate';
import { requireSocietyAccess } from '../../../middleware/authorize';
import { asyncHandler } from '../../../utils/async-handler';
import {
  getSocietyHandler,
  listFlatsHandler,
  listWingsHandler,
} from '../controllers/society.controller';

/**
 * Foundation read endpoints for society isolation checks.
 * Full society management arrives in later phases.
 */
const router = Router();

router.get(
  '/:societyId',
  authenticate,
  requireSocietyAccess('societyId'),
  asyncHandler(getSocietyHandler),
);

router.get(
  '/:societyId/wings',
  authenticate,
  requireSocietyAccess('societyId'),
  asyncHandler(listWingsHandler),
);

router.get(
  '/:societyId/flats',
  authenticate,
  requireSocietyAccess('societyId'),
  asyncHandler(listFlatsHandler),
);

export default router;
