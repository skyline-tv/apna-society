export interface CreateOrderInput {
  amountPaise: number;
  currency?: string;
  receipt: string;
  notes?: Record<string, string>;
}

export interface CreateOrderResult {
  orderId: string;
  amountPaise: number;
  currency: string;
  provider: string;
  keyId?: string;
}

export interface VerifyPaymentInput {
  orderId: string;
  paymentId: string;
  signature: string;
}

export interface WebhookEvent {
  eventId: string;
  eventType: string;
  orderId?: string;
  paymentId?: string;
  status?: string;
  amountPaise?: number;
  raw: unknown;
}

export interface PaymentProvider {
  readonly name: string;
  createOrder(input: CreateOrderInput): Promise<CreateOrderResult>;
  verifyPaymentSignature(input: VerifyPaymentInput): boolean;
  verifyWebhookSignature(rawBody: string | Buffer, signature: string): boolean;
  parseWebhook(payload: unknown): WebhookEvent;
}
