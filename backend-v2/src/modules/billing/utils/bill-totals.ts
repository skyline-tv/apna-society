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
