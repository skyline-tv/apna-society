/** Backend-authoritative bill total: maintenance + additional services + adjustments. */
export function billComputedTotalPaise(input: {
  baseAmountPaise: number;
  additionalServicesTotalPaise?: number;
  adjustmentsPaise: number;
}): number {
  return (
    input.baseAmountPaise +
    (input.additionalServicesTotalPaise ?? 0) +
    input.adjustmentsPaise
  );
}

export type BillPayableInput = {
  outstandingPrincipalPaise: number;
  interestAccruedPaise: number;
  interestPaidPaise?: number;
  status: string;
};

/**
 * Unpaid interest still due.
 *
 * `interestAccruedPaise` is the lifetime simple-interest total from the principal
 * ledger. It is not reduced when interest is collected. Remaining due is
 * accrued minus confirmed interest allocations.
 *
 * Legacy bills were marked PAID when principal hit zero, while accrued stayed
 * as a historical total and `interestPaidPaise` was never stored. Those bills
 * are fully settled — do not resurrect that snapshot as outstanding.
 */
export function unpaidInterestPaise(bill: BillPayableInput): number {
  const accrued = Math.max(0, bill.interestAccruedPaise);
  const paid = Math.max(0, bill.interestPaidPaise ?? 0);
  if (bill.status === 'CANCELLED') return 0;
  if (bill.status === 'PAID' && bill.outstandingPrincipalPaise <= 0 && paid === 0) {
    return 0;
  }
  return Math.max(0, accrued - paid);
}

/** Confirmed remaining payable: unpaid principal + unpaid interest. */
export function billOutstandingPayablePaise(bill: BillPayableInput): number {
  if (bill.status === 'CANCELLED') return 0;
  return Math.max(0, bill.outstandingPrincipalPaise) + unpaidInterestPaise(bill);
}
