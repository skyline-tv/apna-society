import { createHmac, timingSafeEqual } from 'crypto';
import { getEnv, isLivePaymentsEnabled } from '../../../config/env';
import { forbidden } from '../../../shared/errors/app-error';
import type {
  CreateOrderInput,
  CreateOrderResult,
  PaymentProvider,
  VerifyPaymentInput,
  WebhookEvent,
} from './payment-provider';

function safeEqualHex(a: string, b: string): boolean {
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

/**
 * Live Razorpay Orders API provider.
 * Requires PAYMENT_GATEWAY_PROVIDER=razorpay and PAYMENTS_LIVE_ENABLED=true
 * before createOrder will charge against the live API.
 */
export class RazorpayProvider implements PaymentProvider {
  readonly name = 'razorpay';

  private get keyId(): string {
    return getEnv().RAZORPAY_KEY_ID;
  }

  private get keySecret(): string {
    return getEnv().RAZORPAY_KEY_SECRET;
  }

  private get webhookSecret(): string {
    return getEnv().RAZORPAY_WEBHOOK_SECRET;
  }

  async createOrder(input: CreateOrderInput): Promise<CreateOrderResult> {
    if (!isLivePaymentsEnabled()) {
      throw forbidden(
        'Live Razorpay payments are not enabled. Set PAYMENT_GATEWAY_PROVIDER=razorpay and PAYMENTS_LIVE_ENABLED=true with valid secrets.',
        'PAYMENTS_LIVE_DISABLED',
      );
    }

    const auth = Buffer.from(`${this.keyId}:${this.keySecret}`).toString('base64');
    const response = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: input.amountPaise,
        currency: input.currency ?? 'INR',
        receipt: input.receipt.slice(0, 40),
        notes: input.notes,
      }),
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`Razorpay order create failed (${response.status}): ${body.slice(0, 200)}`);
    }

    const data = (await response.json()) as {
      id: string;
      amount: number;
      currency: string;
    };

    return {
      orderId: data.id,
      amountPaise: data.amount,
      currency: data.currency,
      provider: this.name,
      keyId: this.keyId,
    };
  }

  verifyPaymentSignature(input: VerifyPaymentInput): boolean {
    const body = `${input.orderId}|${input.paymentId}`;
    const expected = createHmac('sha256', this.keySecret).update(body).digest('hex');
    return safeEqualHex(expected, input.signature);
  }

  verifyWebhookSignature(rawBody: string | Buffer, signature: string): boolean {
    const expected = createHmac('sha256', this.webhookSecret).update(rawBody).digest('hex');
    return safeEqualHex(expected, signature);
  }

  parseWebhook(payload: unknown): WebhookEvent {
    const body = payload as {
      event?: string;
      id?: string;
      payload?: {
        payment?: {
          entity?: {
            id?: string;
            order_id?: string;
            status?: string;
            amount?: number;
          };
        };
      };
    };
    const entity = body.payload?.payment?.entity;
    return {
      eventId: body.id ?? `evt_${entity?.id ?? 'unknown'}`,
      eventType: body.event ?? 'payment.captured',
      orderId: entity?.order_id,
      paymentId: entity?.id,
      status: entity?.status,
      amountPaise: entity?.amount,
      raw: payload,
    };
  }
}
