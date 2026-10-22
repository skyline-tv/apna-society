import { createHmac, randomUUID, timingSafeEqual } from 'crypto';
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
 * Mock Razorpay-compatible provider for development, tests, and deployed
 * environments until live Razorpay is opted in. Never used for live charges.
 */
export class MockRazorpayProvider implements PaymentProvider {
  readonly name = 'razorpay-mock';

  private get secret(): string {
    if (isLivePaymentsEnabled()) {
      throw forbidden(
        'Mock payment provider cannot be used when live payments are enabled',
        'DEMO_PAYMENTS_DISABLED',
      );
    }
    return getEnv().RAZORPAY_KEY_SECRET || 'test_razorpay_secret';
  }

  private get webhookSecret(): string {
    const env = getEnv();
    return env.RAZORPAY_WEBHOOK_SECRET || this.secret;
  }

  async createOrder(input: CreateOrderInput): Promise<CreateOrderResult> {
    const env = getEnv();
    if (isLivePaymentsEnabled()) {
      throw forbidden(
        'Online payment orders are disabled. Enable PAYMENTS_LIVE_ENABLED=true with Razorpay credentials.',
        'PAYMENTS_LIVE_DISABLED',
      );
    }
    const orderId = `order_${randomUUID().replace(/-/g, '').slice(0, 14)}`;
    return {
      orderId,
      amountPaise: input.amountPaise,
      currency: input.currency ?? 'INR',
      provider: this.name,
      keyId: env.RAZORPAY_KEY_ID || 'rzp_test_mock',
    };
  }

  verifyPaymentSignature(input: VerifyPaymentInput): boolean {
    const body = `${input.orderId}|${input.paymentId}`;
    const expected = createHmac('sha256', this.secret).update(body).digest('hex');
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
      eventId: body.id ?? `evt_${entity?.id ?? randomUUID()}`,
      eventType: body.event ?? 'payment.captured',
      orderId: entity?.order_id,
      paymentId: entity?.id,
      status: entity?.status,
      amountPaise: entity?.amount,
      raw: payload,
    };
  }
}

/** Helper for tests to craft a valid payment signature. */
export function signMockPayment(orderId: string, paymentId: string, secret?: string): string {
  const key = secret ?? (getEnv().RAZORPAY_KEY_SECRET || 'test_razorpay_secret');
  return createHmac('sha256', key).update(`${orderId}|${paymentId}`).digest('hex');
}

export function signMockWebhook(rawBody: string, secret?: string): string {
  const key =
    secret ??
    (getEnv().RAZORPAY_WEBHOOK_SECRET || getEnv().RAZORPAY_KEY_SECRET || 'test_razorpay_secret');
  return createHmac('sha256', key).update(rawBody).digest('hex');
}
