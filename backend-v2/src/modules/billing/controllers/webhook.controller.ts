import type { Request, Response } from 'express';
import { handleGatewayWebhook } from '../services/payment.service';

export async function paymentWebhookHandler(req: Request, res: Response): Promise<void> {
  const signature = req.header('x-razorpay-signature') ?? '';
  const rawBody =
    typeof (req as Request & { rawBody?: string }).rawBody === 'string'
      ? (req as Request & { rawBody: string }).rawBody
      : JSON.stringify(req.body);
  const societyHint = req.header('x-society-id')?.trim();
  const data = await handleGatewayWebhook(societyHint, rawBody, signature, req.body);
  res.json({ success: true, data });
}
