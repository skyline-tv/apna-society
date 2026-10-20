import { isLivePaymentsEnabled } from '../../../config/env';
import { getLogger } from '../../../utils/logger';
import { MockRazorpayProvider } from './mock-razorpay.provider';
import type { PaymentProvider } from './payment-provider';
import { RazorpayProvider } from './razorpay.provider';

let provider: PaymentProvider | null = null;

export function createPaymentProvider(): PaymentProvider {
  if (isLivePaymentsEnabled()) {
    getLogger().info('Using live Razorpay payment provider');
    return new RazorpayProvider();
  }
  getLogger().info(
    'Using mock payment provider (online charges disabled until PAYMENTS_LIVE_ENABLED=true)',
  );
  return new MockRazorpayProvider();
}

export function getPaymentProvider(): PaymentProvider {
  if (!provider) provider = createPaymentProvider();
  return provider;
}

export function setPaymentProvider(next: PaymentProvider): void {
  provider = next;
}

export function resetPaymentProvider(): void {
  provider = null;
}
