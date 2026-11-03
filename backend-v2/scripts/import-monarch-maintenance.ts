/**
 * Record Monarch maintenance offline payments against existing bills.
 *
 * Does not create or cancel bills. For each sheet row, applies amountRupees
 * FIFO across the flat's outstanding (non-cancelled) bills.
 *
 * BANK → NEFT, CASH → CASH. Idempotent via payment keys.
 *
 * Usage:
 *   npm run import:monarch-maintenance -- --confirm
 *   npm run import:monarch-maintenance -- --confirm --paid-at 2026-11-01
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
import { recordOfflinePayment } from '../src/modules/billing/services/payment.service';
import { rupeesIntegerToPaise } from '../src/modules/billing/utils/money';

const SOCIETY_CODE = 'MONARCH_SOLITAIRE';
const DEFAULT_PAID_AT = '2026-11-01';

type RosterRow = {
  wing: string;
  flat: string;
  amountRupees: number;
  months?: number;
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

function parsePaidAt(raw: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw.trim());
  if (!match) {
    throw new Error('--paid-at must be YYYY-MM-DD');
  }
  return new Date(`${raw.trim()}T00:00:00.000+05:30`);
}

async function main(): Promise<void> {
  if (!process.argv.includes('--confirm')) {
    throw new Error('Refusing to run. Pass --confirm to record maintenance payments.');
  }

  loadEnv();
  await connectDatabase();

  const paidAtRaw = arg('paid-at') ?? arg('from') ?? DEFAULT_PAID_AT;
  const paidAt = parsePaidAt(paidAtRaw);
  const roster = loadRoster();

  const society = await SocietyModel.findOne({ code: SOCIETY_CODE });
  if (!society) {
    throw new Error(`Society ${SOCIETY_CODE} not found. Run npm run seed first.`);
  }
  const societyId = String(society._id);

  const admin = await UserModel.findOne({ roles: 'ADMIN', isActive: true }).select('_id').lean();
  if (!admin) {
    throw new Error('No admin user found. Run reset:launch or prepare:admin first.');
  }
  const actor = { userId: String(admin._id) };

  const summary = {
    paidAt: paidAtRaw,
    totalRows: roster.length,
    paid: 0,
    alreadyPaid: 0,
    skipped: 0,
    remainingUnappliedRupees: 0,
    errors: [] as Array<{ flat: string; error: string }>,
    payments: [] as Array<{
      flat: string;
      amountRupees: number;
      appliedRupees: number;
      method: string;
      billPayments: Array<{ billId: string; billNumber?: string; amountRupees: number; paymentId?: string }>;
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

      const amountPaise = rupeesIntegerToPaise(row.amountRupees);
      const paymentMethod = mapMethod(row.method);

      const bills = await BillModel.find({
        societyId: society._id,
        flatId: flat._id,
        status: { $nin: ['CANCELLED', 'PAID'] },
        outstandingPrincipalPaise: { $gt: 0 },
      }).sort({ billingPeriodStart: 1, createdAt: 1 });

      if (bills.length === 0) {
        summary.errors.push({ flat: number, error: 'No outstanding bills to pay' });
        continue;
      }

      let remainingPaise = amountPaise;
      let appliedPaise = 0;
      const billPayments: Array<{
        billId: string;
        billNumber?: string;
        amountRupees: number;
        paymentId?: string;
      }> = [];

      for (const bill of bills) {
        if (remainingPaise <= 0) break;

        // Re-read outstanding in case a prior payment in this loop settled interest-only edges.
        const live = await BillModel.findById(bill._id);
        if (!live || live.status === 'CANCELLED' || live.status === 'PAID') continue;
        if (live.outstandingPrincipalPaise <= 0) continue;

        const chunkPaise = Math.min(remainingPaise, live.outstandingPrincipalPaise);
        const idempotencyKey = `monarch-maint-pay-${number}-${String(live._id)}-${chunkPaise}-${row.method}`;

        const paid = await recordOfflinePayment(
          societyId,
          {
            billId: String(live._id),
            amountPaise: chunkPaise,
            paidAt,
            paymentMethod,
            referenceNumber: `SEED-${number}-${paidAtRaw}`,
            notes: `Seeded from maintenance sheet (${row.method})`,
            idempotencyKey,
          },
          actor,
        );

        if (paid.alreadySettled) summary.alreadyPaid += 1;
        else summary.paid += 1;

        billPayments.push({
          billId: String(live._id),
          billNumber: live.billNumber,
          amountRupees: chunkPaise / 100,
          paymentId: paid.paymentId,
        });

        remainingPaise -= chunkPaise;
        appliedPaise += chunkPaise;
      }

      if (appliedPaise === 0 && remainingPaise === amountPaise) {
        summary.alreadyPaid += 1;
      }

      summary.remainingUnappliedRupees += remainingPaise / 100;
      if (remainingPaise > 0) {
        summary.errors.push({
          flat: number,
          error: `Applied ₹${appliedPaise / 100} of ₹${row.amountRupees}; ₹${remainingPaise / 100} left (not enough outstanding)`,
        });
      }

      summary.payments.push({
        flat: number,
        amountRupees: row.amountRupees,
        appliedRupees: appliedPaise / 100,
        method: paymentMethod,
        billPayments,
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
