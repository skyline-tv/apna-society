import { conflict } from '../../../shared/errors/app-error';
import { BillModel } from '../models/bill.model';
import { PaymentModel } from '../models/payment.model';
import { ReceiptModel } from '../models/receipt.model';
import { parseObjectId } from '../../../utils/object-id';

/**
 * Hard financial checks. Discrepancies throw — they are never silently discarded.
 */
export function assertBillFinancialInvariants(input: {
  baseAmountPaise: number;
  adjustmentsPaise: number;
  totalAmountPaise: number;
  amountPaidPaise: number;
  outstandingPrincipalPaise: number;
  paymentAllocatedPrincipalPaise?: number;
  paymentAmountPaise?: number;
}): void {
  if (input.totalAmountPaise !== input.baseAmountPaise + input.adjustmentsPaise) {
    throw conflict(
      'Bill total does not equal base + adjustments',
      'INVARIANT_TOTAL_MISMATCH',
    );
  }
  if (input.outstandingPrincipalPaise < 0) {
    throw conflict('Outstanding principal is negative', 'INVARIANT_NEGATIVE_PRINCIPAL');
  }
  if (input.amountPaidPaise < 0) {
    throw conflict('Amount paid is negative', 'INVARIANT_NEGATIVE_PAID');
  }
  if (input.amountPaidPaise + input.outstandingPrincipalPaise !== input.totalAmountPaise) {
    throw conflict(
      'amountPaid + outstandingPrincipal must equal totalAmount',
      'INVARIANT_BALANCE_EQUATION',
    );
  }
  if (
    input.paymentAllocatedPrincipalPaise !== undefined &&
    input.paymentAmountPaise !== undefined &&
    input.paymentAllocatedPrincipalPaise > input.paymentAmountPaise
  ) {
    throw conflict(
      'Principal allocation exceeds payment amount',
      'INVARIANT_ALLOCATION_OVERFLOW',
    );
  }
}

export async function reconcileBillFinancials(societyId: string, billId: string) {
  const bill = await BillModel.findOne({
    _id: parseObjectId(billId, 'billId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!bill) {
    throw conflict('Bill not found for reconciliation', 'BILL_NOT_FOUND');
  }

  assertBillFinancialInvariants({
    baseAmountPaise: bill.baseAmountPaise,
    adjustmentsPaise: bill.adjustmentsPaise,
    totalAmountPaise: bill.totalAmountPaise,
    amountPaidPaise: bill.amountPaidPaise,
    outstandingPrincipalPaise: bill.outstandingPrincipalPaise,
  });

  const successPayments = await PaymentModel.find({
    billId: bill._id,
    status: 'SUCCESS',
  }).lean();

  const allocatedPrincipal = successPayments.reduce(
    (sum, p) => sum + p.allocatedToPrincipalPaise,
    0,
  );
  if (allocatedPrincipal !== bill.amountPaidPaise) {
    throw conflict(
      'Successful payment principal allocations do not match bill.amountPaidPaise',
      'INVARIANT_PAYMENT_RECONCILIATION',
    );
  }

  for (const payment of successPayments) {
    const receipt = await ReceiptModel.findOne({ paymentId: payment._id }).lean();
    if (!receipt) {
      throw conflict('Successful payment is missing a receipt', 'INVARIANT_MISSING_RECEIPT');
    }
    if (receipt.amountPaise !== payment.amountPaise) {
      throw conflict(
        'Receipt amount does not match payment amount',
        'INVARIANT_RECEIPT_AMOUNT',
      );
    }
  }

  const pendingOrFailed = await PaymentModel.find({
    billId: bill._id,
    status: { $in: ['PENDING', 'FAILED'] },
  }).lean();
  for (const payment of pendingOrFailed) {
    const receipt = await ReceiptModel.findOne({ paymentId: payment._id }).lean();
    if (receipt) {
      throw conflict(
        'Pending/failed payment must not have a receipt',
        'INVARIANT_INVALID_RECEIPT',
      );
    }
  }

  return {
    billId: String(bill._id),
    ok: true as const,
    amountPaidPaise: bill.amountPaidPaise,
    outstandingPrincipalPaise: bill.outstandingPrincipalPaise,
    successfulPayments: successPayments.length,
  };
}
