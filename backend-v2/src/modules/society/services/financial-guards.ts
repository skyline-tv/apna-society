import mongoose from 'mongoose';

/**
 * Billing is not implemented yet. When a Bill model is registered later,
 * deactivation safeguards will consult outstanding balances here.
 */
export async function hasOutstandingFinancialRecords(
  societyId: string,
  flatId: string,
): Promise<boolean> {
  const billModel = mongoose.models.Bill;
  if (!billModel) {
    return false;
  }

  const outstanding = await billModel
    .countDocuments({
      societyId,
      flatId,
      status: { $in: ['DUE', 'OVERDUE', 'PARTIAL'] },
    })
    .exec();
  return outstanding > 0;
}
