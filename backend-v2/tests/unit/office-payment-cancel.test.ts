import { describe, expect, it } from 'vitest';
import { isOfficeRecordedPayment } from '../../src/modules/billing/models/payment.model';

describe('isOfficeRecordedPayment', () => {
  it('allows cash/cheque/NEFT/UPI/offline with no gateway order', () => {
    expect(isOfficeRecordedPayment({ paymentMethod: 'CASH' })).toBe(true);
    expect(isOfficeRecordedPayment({ paymentMethod: 'CHEQUE' })).toBe(true);
    expect(isOfficeRecordedPayment({ paymentMethod: 'NEFT' })).toBe(true);
    expect(isOfficeRecordedPayment({ paymentMethod: 'UPI' })).toBe(true);
    expect(isOfficeRecordedPayment({ paymentMethod: 'OFFLINE' })).toBe(true);
  });

  it('rejects gateway checkout payments even when the method is UPI', () => {
    expect(
      isOfficeRecordedPayment({ paymentMethod: 'UPI', gatewayOrderId: 'order_live_1' }),
    ).toBe(false);
  });
});
