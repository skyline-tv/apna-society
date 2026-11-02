export function billedMonthsProgress(bill: {
  monthlyRatePaise: number;
  numberOfMonths: number;
  baseAmountPaise: number;
  amountPaidPaise: number;
  outstandingPrincipalPaise: number;
  status: string;
}): { paidMonths: number; pendingMonths: number } {
  if (bill.status === 'PAID' || bill.status === 'CANCELLED' || bill.outstandingPrincipalPaise <= 0) {
    return { paidMonths: bill.numberOfMonths, pendingMonths: 0 };
  }
  if (bill.monthlyRatePaise <= 0 || bill.numberOfMonths <= 0) {
    return { paidMonths: 0, pendingMonths: Math.max(0, bill.numberOfMonths) };
  }
  const paidTowardBase = Math.min(Math.max(0, bill.amountPaidPaise), bill.baseAmountPaise);
  const paidMonths = Math.min(
    bill.numberOfMonths,
    Math.floor(paidTowardBase / bill.monthlyRatePaise),
  );
  return { paidMonths, pendingMonths: bill.numberOfMonths - paidMonths };
}
