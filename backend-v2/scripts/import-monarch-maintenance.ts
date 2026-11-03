/**
 * Seed Monarch maintenance bills + offline payments from the office sheet.
 *
 * For each row with an amount + months:
 * - months must be 1–12 and match amountRupees / flat.maintenanceRate
 * - generate a bill for that many months from --from (1st of month)
 * - record a full offline payment (BANK → NEFT, CASH → CASH)
 *
 * Rows without an amount are omitted from the JSON. Idempotent via payment keys.
 *
 * Usage:
 *   npm run import:monarch-maintenance -- --confirm
 *   npm run import:monarch-maintenance -- --confirm --from 2026-11-01
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadEnv } from '../src/config/env';
import { connectDatabase, disconnectDatabase } from '../src/database/connection';
import { SocietyModel } from '../src/modules/society/models/society.model';
import { FlatModel } from '../src/modules/society/models/flat.model';
import { UserModel } from '../src/modules/users/models/user.model';
import { generateBillForFlat } from '../src/modules/billing/services/bill-generation.service';
import { recordOfflinePayment } from '../src/modules/billing/services/payment.service';
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
  // Noon UTC avoids DST edge cases; billing calendar normalizes to society TZ.
  return new Date(`${raw.trim()}T00:00:00.000+05:30`);
}

async function main(): Promise<void> {
  if (!process.argv.includes('--confirm')) {
    throw new Error('Refusing to run. Pass --confirm to seed maintenance bills and payments.');
  }

  loadEnv();
  await connectDatabase();

  const fromRaw = arg('from') ?? DEFAULT_FROM;
  const periodStart = parsePeriodStart(fromRaw);
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
    from: fromRaw,
    totalRows: roster.length,
    billed: 0,
    reusedBills: 0,
    paid: 0,
    alreadyPaid: 0,
    skipped: 0,
    errors: [] as Array<{ flat: string; error: string }>,
    payments: [] as Array<{
      flat: string;
      months: number;
      amountRupees: number;
      method: string;
      billId: string;
      paymentId?: string;
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
        summary.errors.push({
          flat: number,
          error: `Months ${months} out of range 1–12`,
        });
        continue;
      }
      if (!Number.isInteger(rate) || rate <= 0 || rate * months !== row.amountRupees) {
        summary.errors.push({
          flat: number,
          error: `Amount ₹${row.amountRupees} for ${months} month(s) does not match rate ₹${rate}`,
        });
        continue;
      }

      const generated = await generateBillForFlat(
        societyId,
        {
          flatId: String(flat._id),
          billingPeriodStart: periodStart,
          numberOfMonths: months,
          notes: `Monarch opening maintenance seed (${row.method})`,
        },
        actor,
      );
      if (generated.created) summary.billed += 1;
      else summary.reusedBills += 1;

      const billId = generated.bill.id as string;
      const amountPaise = rupeesIntegerToPaise(row.amountRupees);
      const paymentMethod = mapMethod(row.method);
      const idempotencyKey = `monarch-maint-${number}-${fromRaw}-${months}-${row.method}`;

      const paid = await recordOfflinePayment(
        societyId,
        {
          billId,
          amountPaise,
          paidAt: periodStart,
          paymentMethod,
          referenceNumber: `SEED-${number}-${fromRaw}`,
          notes: `Seeded from maintenance sheet (${row.method})`,
          idempotencyKey,
        },
        actor,
      );

      if (paid.alreadySettled) summary.alreadyPaid += 1;
      else summary.paid += 1;

      summary.payments.push({
        flat: number,
        months,
        amountRupees: row.amountRupees,
        method: paymentMethod,
        billId,
        paymentId: paid.paymentId,
      });
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
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
