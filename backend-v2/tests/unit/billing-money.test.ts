import { describe, expect, it } from 'vitest';
import {
  calculateSimpleDailyInterestPaise,
  multiplyPaise,
  paiseToRupeesDisplay,
  rupeesIntegerToPaise,
} from '../../src/modules/billing/utils/money';
import {
  billOutstandingPayablePaise,
  unpaidInterestPaise,
} from '../../src/modules/billing/utils/bill-totals';
import { buildReceiptPdf } from '../../src/modules/billing/services/pdf.service';
import {
  billingPeriodBounds,
  dueDateForBillingPeriod,
  overdueDaysAsOf,
  zonedMidnight,
} from '../../src/modules/billing/utils/billing-calendar';

describe('money utils', () => {
  it('converts integer rupees to paise without floats', () => {
    expect(rupeesIntegerToPaise(4000)).toBe(400_000);
    expect(rupeesIntegerToPaise(5000)).toBe(500_000);
    expect(multiplyPaise(400_000, 3)).toBe(1_200_000);
    expect(paiseToRupeesDisplay(588_000_00)).toBe('588000.00');
  });

  it('computes simple daily interest with floor via bigint', () => {
    // 400000 paise * 2400 bps * 1 day / (10000 * 365) = 263.013... → 263
    expect(calculateSimpleDailyInterestPaise(400_000, 1, 2400)).toBe(263);
    expect(calculateSimpleDailyInterestPaise(400_000, 0, 2400)).toBe(0);
    expect(calculateSimpleDailyInterestPaise(0, 10, 2400)).toBe(0);
  });
});

describe('outstanding payable', () => {
  it('treats lifetime accrued interest as unpaid until interest is collected', () => {
    expect(
      unpaidInterestPaise({
        outstandingPrincipalPaise: 400_000,
        interestAccruedPaise: 1_200,
        interestPaidPaise: 0,
        status: 'OVERDUE',
      }),
    ).toBe(1_200);
    expect(
      billOutstandingPayablePaise({
        outstandingPrincipalPaise: 200_000,
        interestAccruedPaise: 1_200,
        interestPaidPaise: 400,
        status: 'PARTIALLY_PAID',
      }),
    ).toBe(200_800);
  });

  it('shows zero outstanding on a fully paid bill even if accrued interest remains as history', () => {
    expect(
      billOutstandingPayablePaise({
        outstandingPrincipalPaise: 0,
        interestAccruedPaise: 5_000,
        interestPaidPaise: 0,
        status: 'PAID',
      }),
    ).toBe(0);
    expect(
      billOutstandingPayablePaise({
        outstandingPrincipalPaise: 0,
        interestAccruedPaise: 5_000,
        interestPaidPaise: 5_000,
        status: 'PAID',
      }),
    ).toBe(0);
  });
});

describe('receipt pdf', () => {
  it('builds a PDF with branding, flat, status and paid total', () => {
    const pdf = buildReceiptPdf({
      receiptNumber: 'RCPT-2026-000001',
      societyName: 'Monarch Solitaire A to E',
      flatNumber: '303',
      wingCode: 'E',
      ownerName: 'Owner One',
      amountPaise: 401_200,
      paymentMethod: 'UPI',
      transactionReference: 'pay_abc',
      paidAt: new Date('2026-07-15T10:30:00.000+05:30'),
      billNumber: 'BILL-2026-000001',
      billingPeriod: '01 Jul 2026 - 31 Jul 2026',
      baseAmountPaise: 400_000,
      interestAmountPaise: 1_200,
      paymentStatus: 'SUCCESSFUL',
    });
    const text = pdf.toString('utf8');
    expect(text.startsWith('%PDF-1.4')).toBe(true);
    expect(text).toContain('Apna Society');
    expect(text).toContain('AS  -  Apna Society');
    expect(text).toContain('Monarch Solitaire A to E');
    expect(text).toContain('E-303');
    expect(text).toContain('RCPT-2026-000001');
    expect(text).toContain('SUCCESSFUL');
    expect(text).toContain('BILL-2026-000001');
    expect(text).toContain('pay_abc');
    expect(text).toContain('authorized receipt');
    expect(text).toContain('MediaBox [0 0 595 842]');
  });

  it('omits empty transaction references and wraps long payer names', () => {
    const pdf = buildReceiptPdf({
      receiptNumber: 'COLRCPT-2026-000013',
      societyName: 'Monarch Solitaire A to E',
      flatNumber: '303',
      wingCode: 'E',
      ownerName: 'Rajeshkumar Venkateshwaran Subramaniam',
      amountPaise: 1_250_000,
      paymentMethod: 'CASH',
      paidAt: new Date('2026-07-15T10:30:00.000+05:30'),
      collectionNumber: 'COL-2026-0004',
      collectionTitle: 'External plaster, terrace waterproofing and compound drainage repair',
      paymentStatus: 'SUCCESSFUL',
    });
    const text = pdf.toString('utf8');
    expect(text).toContain('One-time collection');
    expect(text).toContain('Special collection');
    expect(text).toContain('COL-2026-0004');
    expect(text).toContain('Rajeshkumar');
    expect(text).not.toContain('Transaction reference');
    expect(text).not.toContain('Base maintenance');
  });

  it('shows applied principal on a partial payment instead of the full bill base', () => {
    const pdf = buildReceiptPdf({
      receiptNumber: 'RCPT-2026-000042',
      societyName: 'Monarch Solitaire A to E',
      flatNumber: '303',
      wingCode: 'E',
      ownerName: 'Priya Sharma',
      amountPaise: 202_630,
      paymentMethod: 'BANK_TRANSFER',
      transactionReference: 'NEFT-441902',
      paidAt: new Date('2026-07-15T10:30:00.000+05:30'),
      billNumber: 'BILL-2026-000001',
      billingPeriod: 'Apr 2026',
      baseAmountPaise: 400_000,
      additionalServicesPaise: 50_000,
      principalAmountPaise: 200_000,
      interestAmountPaise: 2_630,
      paymentStatus: 'SUCCESSFUL',
    });
    const text = pdf.toString('utf8');
    expect(text).toContain('Applied to principal');
    expect(text).toContain('Interest');
    expect(text).not.toContain('Base maintenance');
  });
});

describe('billing calendar', () => {
  it('builds one-month and three-month calendar periods in IST', () => {
    const start = zonedMidnight(2026, 4, 1);
    const one = billingPeriodBounds(start, 1);
    expect(one.periodStart.toISOString()).toBe(zonedMidnight(2026, 4, 1).toISOString());
    expect(one.periodEnd.toISOString()).toBe(
      new Date('2026-04-30T23:59:59.999+05:30').toISOString(),
    );

    const three = billingPeriodBounds(start, 3);
    expect(three.periodEnd.toISOString()).toBe(
      new Date('2026-06-30T23:59:59.999+05:30').toISOString(),
    );

    const due = dueDateForBillingPeriod(start);
    expect(due.toISOString()).toBe(new Date('2026-04-10T23:59:59.999+05:30').toISOString());
  });

  it('counts overdue days from the 11th', () => {
    const due = new Date('2026-04-10T23:59:59.999+05:30');
    expect(overdueDaysAsOf(due, new Date('2026-04-10T12:00:00+05:30'))).toBe(0);
    expect(overdueDaysAsOf(due, new Date('2026-04-11T00:00:00+05:30'))).toBe(1);
    expect(overdueDaysAsOf(due, new Date('2026-04-12T23:00:00+05:30'))).toBe(2);
  });
});
