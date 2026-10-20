import { Router } from 'express';
import { asyncHandler } from '../../../utils/async-handler';
import { paymentWebhookHandler } from '../controllers/webhook.controller';

const router = Router();

router.post('/payments', asyncHandler(paymentWebhookHandler));

export default router;
