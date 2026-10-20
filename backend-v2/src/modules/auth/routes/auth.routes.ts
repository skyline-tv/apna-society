import { Router } from 'express';
import { asyncHandler } from '../../../utils/async-handler';
import { authenticate } from '../../../middleware/authenticate';
import { authRateLimiter } from '../../../middleware/rate-limit';
import { validateBody } from '../../../middleware/validate';
import {
  logoutAllHandler,
  logoutHandler,
  meHandler,
  refreshHandler,
  requestOtpHandler,
  verifyOtpHandler,
} from '../controllers/auth.controller';
import {
  logoutSchema,
  refreshSchema,
  requestOtpSchema,
  verifyOtpSchema,
} from '../validators/auth.validators';

const router = Router();

router.post(
  '/request-otp',
  authRateLimiter,
  validateBody(requestOtpSchema),
  asyncHandler(requestOtpHandler),
);

router.post(
  '/verify-otp',
  authRateLimiter,
  validateBody(verifyOtpSchema),
  asyncHandler(verifyOtpHandler),
);

router.post(
  '/refresh',
  authRateLimiter,
  validateBody(refreshSchema),
  asyncHandler(refreshHandler),
);

router.post(
  '/logout',
  validateBody(logoutSchema),
  asyncHandler(logoutHandler),
);

router.post('/logout-all', authenticate, asyncHandler(logoutAllHandler));

router.get('/me', authenticate, asyncHandler(meHandler));

export default router;
