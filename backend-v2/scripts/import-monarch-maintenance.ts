/**
 * Record Monarch maintenance payments for the prepaid months on the sheet.
 *
 * For each flat:
 * - Prefer an existing non-cancelled bill
 * - If more months are needed than the bill currently covers, extend that bill
 * - Then record an offline payment for the remaining amount (unique reference each time)
 *
 * Example A-604 (₹30,000 / 6 months): if ₹15,000 / 3 months is already paid,
 * extends by 3 months and records a second ₹15,000 payment on the same bill.
 *
 * Usage:
 *   npm run import:monarch-maintenance -- --confirm
 *   npm run import:monarch-maintenance -- --confirm --from 2026-11-01
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadEnv } from '../src/config/env';
import { connectDatabase, disconnectDatabase } from '../src/database/connection';
import { AppError } from '../src/shared/errors/app-error';
import { SocietyModel } from '../src/modules/society/models/society.model';
import { FlatModel } from '../src/modules/society/models/flat.model';
import { UserModel } from '../src/modules/users/models/user.model';
import { BillModel } from '../src/modules/billing/models/bill.model';
import {
  extendBillForAdvanceMonths,
  generateBillForFlat,
} from '../src/modules/billing/services/bill-generation.service';
import { recordOfflinePayment } from '../src/modules/billing/services/payment.service';
import { billingPeriodBounds } from '../src/modules/billing/utils/billing-calendar';
import { billedMonthsProgress } from '../src/modules/billing/utils/bill-months';
import { rupeesIntegerToPaise } from '../src/modules/billing/utils/money';

const SOCIETY_CODE = 'MONARCH_SOLITAIRE';
const DEFAULT_FROM = '2026-11-01';

type RosterRow = {
  wing: string;
  flat: string;
  amountRupees: number;
  months: number;
  method: 'BANK' | 'CASH';
};

function arg(name: string): string | undefined {
  const idx = process.argv.indexOf(`--${name}`);
  if (idx === -1) return undefined;
  return process.argv[idx + 1];
}

function flatNumber(wing: string, flat: string): string {
  return `${wing.toUpperCase()}-${flat}`;
}

function mapMethod(method: 'BANK' | 'CASH'): 'NEFT' | 'CASH' {
  return method === 'BANK' ? 'NEFT' : 'CASH';
}

function loadRoster(): RosterRow[] {
  const path = resolve(__dirname, 'data/monarch-maintenance-payments.json');
  return JSON.parse(readFileSync(path, 'utf8')) as RosterRow[];
}

function parsePeriodStart(raw: string): Date {
  const match = /^(\d{4})-(\d{2})-01$/.exec(raw.trim());
  if (!match) {
    throw new Error('--from must be YYYY-MM-01 (1st of a calendar month)');
  }
  return new Date(`${raw.trim()}T00:00:00.000+05:30`);
}

async function main(): Promise<void> {
  if (!process.argv.includes('--confirm')) {
    throw new Error('Refusing to run. Pass --confirm to record maintenance payments.');
  }

  loadEnv();
  await connectDatabase();

  const fromRaw = arg('from') ?? DEFAULT_FROM;
  const requestedStart = parsePeriodStart(fromRaw);
  const roster = loadRoster();

  const society = await SocietyModel.findOne({ code: SOCIETY_CODE });
  if (!society) {
    throw new Error(`Society ${SOCIETY_CODE} not found. Run npm run seed first.`);
  }
  const societyId = String(society._id);
  const timeZone = society.config?.timezone ?? 'Asia/Kolkata';

  const admin = await UserModel.findOne({ roles: 'ADMIN', isActive: true }).select('_id').lean();
  if (!admin) {
    throw new Error('No admin user found. Run reset:launch or prepare:admin first.');
  }
  const actor = { userId: String(admin._id) };

  const summary = {
    scriptVersion: 'pay-existing-extend-v2',
    from: fromRaw,
    totalRows: roster.length,
    createdBills: 0,
    extendedBills: 0,
    paid: 0,
    alreadyComplete: 0,
    skipped: 0,
    errors: [] as Array<{ flat: string; error: string }>,
    payments: [] as Array<{
      flat: string;
      sheetMonths: number;
      sheetAmountRupees: number;
      previouslyPaidMonths: number;
      monthsAdded: number;
      amountPaidRupees: number;
      billId: string;
      billNumber?: string;
      paymentId?: string;
      method: string;
    }>,
  };

  for (const row of roster) {
    const number = flatNumber(row.wing, row.flat);
    try {
      if (!Number.isInteger(row.amountRupees) || row.amountRupees <= 0) {
        summary.skipped += 1;
        continue;
      }

      const flat = await FlatModel.findOne({ societyId: society._id, number });
      if (!flat) {
        summary.errors.push({ flat: number, error: 'Flat not found' });
        continue;
      }
      if (!flat.activeOwnerUserId || flat.occupancyStatus === 'VACANT') {
        summary.errors.push({
          flat: number,
          error: 'Flat has no active owner — import owners first',
        });
        continue;
      }

      const rate = flat.maintenanceRate;
      const months = row.months;
      if (!Number.isInteger(months) || months < 1 || months > 12) {
        summary.errors.push({ flat: number, error: `Months ${months} out of range 1–12` });
        continue;
      }
      if (!Number.isInteger(rate) || rate <= 0 || rate * months !== row.amountRupees) {
        summary.errors.push({
          flat: number,
          error: `Amount ₹${row.amountRupees} for ${months} month(s) does not match rate ₹${rate}`,
        });
        continue;
      }

      const { periodStart } = billingPeriodBounds(requestedStart, months, timeZone);
      const paymentMethod = mapMethod(row.method);
      const ratePaise = rupeesIntegerToPaise(rate);

      let bill = await BillModel.findOne({
        societyId: society._id,
        flatId: flat._id,
        status: { $ne: 'CANCELLED' },
      }).sort({ billingPeriodStart: 1, createdAt: 1 });

      if (!bill) {
        const generated = await generateBillForFlat(
          societyId,
          {
            flatId: String(flat._id),
            billingPeriodStart: periodStart,
            numberOfMonths: months,
            notes: `Monarch maintenance seed (${row.method})`,
          },
          actor,
        );
        bill = await BillModel.findById(generated.bill.id);
        if (!bill) {
          summary.errors.push({ flat: number, error: 'Bill create returned no document' });
          continue;
        }
        summary.createdBills += 1;
      }

      let progress = billedMonthsProgress(bill);
      const previouslyPaidMonths = progress.paidMonths;
      const monthsNeeded = months - previouslyPaidMonths;

      if (monthsNeeded <= 0 && bill.outstandingPrincipalPaise <= 0) {
        summary.alreadyComplete += 1;
        summary.payments.push({
          flat: number,
          sheetMonths: months,
          sheetAmountRupees: row.amountRupees,
          previouslyPaidMonths,
          monthsAdded: 0,
          amountPaidRupees: 0,
          billId: String(bill._id),
          billNumber: bill.billNumber,
          method: paymentMethod,
        });
        continue;
      }

      // Extend coverage when the sheet needs more months than this bill currently has.
      const extraMonths = Math.max(0, months - bill.numberOfMonths);
      if (extraMonths > 0) {
        bill = await extendBillForAdvanceMonths(societyId, bill, extraMonths, actor);
        summary.extendedBills += 1;
        progress = billedMonthsProgress(bill);
      }

      // Reload so outstanding matches any extension.
      const live = await BillModel.findById(bill._id);
      if (!live) {
        summary.errors.push({ flat: number, error: 'Bill missing after extend' });
        continue;
      }

      const amountPaise = Math.min(
        monthsNeeded > 0 ? monthsNeeded * ratePaise : live.outstandingPrincipalPaise,
        live.outstandingPrincipalPaise,
      );

      if (amountPaise <= 0) {
        summary.alreadyComplete += 1;
        summary.payments.push({
          flat: number,
          sheetMonths: months,
          sheetAmountRupees: row.amountRupees,
          previouslyPaidMonths,
          monthsAdded: extraMonths,
          amountPaidRupees: 0,
          billId: String(live._id),
          billNumber: live.billNumber,
          method: paymentMethod,
        });
        continue;
      }

      // Unique per top-up so a prior SEED-A-604-2026-11-01 payment cannot block this one.
      const ref = `SEED-${number}-${fromRaw}-m${previouslyPaidMonths}-to-${months}`;
      const idempotencyKey = `monarch-maint-pay-${number}-${fromRaw}-${months}-from-${previouslyPaidMonths}-${amountPaise}`;

      const paid = await recordOfflinePayment(
        societyId,
        {
          billId: String(live._id),
          amountPaise,
          paidAt: periodStart,
          paymentMethod,
          referenceNumber: ref,
          notes: `Seeded maintenance top-up (${row.method}): +${amountPaise / 100} toward ${months} months / ₹${row.amountRupees}`,
          idempotencyKey,
        },
        actor,
      );

      if (!paid.alreadySettled) summary.paid += 1;

      summary.payments.push({
        flat: number,
        sheetMonths: months,
        sheetAmountRupees: row.amountRupees,
        previouslyPaidMonths,
        monthsAdded: extraMonths,
        amountPaidRupees: amountPaise / 100,
        billId: String(live._id),
        billNumber: live.billNumber,
        paymentId: paid.paymentId,
        method: paymentMethod,
      });
    } catch (error: unknown) {
      const message =
        error instanceof AppError
          ? `${error.message} (${error.code})`
          : error instanceof Error
            ? error.message
            : String(error);
      summary.errors.push({ flat: number, error: message });
    }
  }

  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  await disconnectDatabase();
}

main().catch(async (error: unknown) => {
  console.error(error);
  await disconnectDatabase().catch(() => undefined);
  process.exit(1);
});
