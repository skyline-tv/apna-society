/**
 * Seed one-time collection "CHS Formation Contribution".
 *
 * - Creates (or reuses) an ALL_FLATS / PER_FLAT collection at ₹5,000 per flat
 * - Records offline payments from scripts/data/monarch-chs-formation.json
 * - BANK → NEFT, CASH → CASH; free-text remarks (e.g. S GHOLAP) go into payment notes
 *
 * Usage:
 *   npm run import:monarch-chs-formation -- --confirm
 *   npm run import:monarch-chs-formation -- --confirm --due 2026-11-01
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadEnv } from '../src/config/env';
import { connectDatabase, disconnectDatabase } from '../src/database/connection';
import { SocietyModel } from '../src/modules/society/models/society.model';
import { FlatModel } from '../src/modules/society/models/flat.model';
import { UserModel } from '../src/modules/users/models/user.model';
import { CollectionModel } from '../src/modules/collections/models/collection.model';
import { CollectionChargeModel } from '../src/modules/collections/models/collection-charge.model';
import { createCollection } from '../src/modules/collections/services/collection.service';
import { recordOfflineCollectionPayment } from '../src/modules/collections/services/collection-payment.service';
import { rupeesIntegerToPaise } from '../src/modules/billing/utils/money';

const SOCIETY_CODE = 'MONARCH_SOLITAIRE';
const COLLECTION_TITLE = 'CHS Formation Contribution';
const PER_FLAT_RUPEES = 5000;
const DEFAULT_DUE = '2026-11-01';

type RosterRow = {
  wing: string;
  flat: string;
  amountRupees: number;
  method: 'BANK' | 'CASH';
  notes?: string;
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
  const path = resolve(__dirname, 'data/monarch-chs-formation.json');
  return JSON.parse(readFileSync(path, 'utf8')) as RosterRow[];
}

function parseDate(raw: string): Date {
  const match = /^(\d{4})-(\d{2})-01$/.exec(raw.trim());
  if (!match) {
    throw new Error('--due must be YYYY-MM-01 (1st of a calendar month)');
  }
  return new Date(`${raw.trim()}T00:00:00.000+05:30`);
}

async function main(): Promise<void> {
  if (!process.argv.includes('--confirm')) {
    throw new Error('Refusing to run. Pass --confirm to seed CHS Formation Contribution.');
  }

  loadEnv();
  await connectDatabase();

  const dueRaw = arg('due') ?? DEFAULT_DUE;
  const dueDate = parseDate(dueRaw);
  const roster = loadRoster();
  const amountPaise = rupeesIntegerToPaise(PER_FLAT_RUPEES);

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

  let collection = await CollectionModel.findOne({
    societyId: society._id,
    title: COLLECTION_TITLE,
    status: { $ne: 'CANCELLED' },
  });

  let collectionCreated = false;
  if (!collection) {
    const created = await createCollection(
      societyId,
      {
        title: COLLECTION_TITLE,
        description:
          'One-time CHS formation contribution for Monarch Solitaire (seeded from office sheet).',
        amountMode: 'PER_FLAT',
        assignmentType: 'ALL_FLATS',
        amountPaise,
        dueDate,
        startDate: dueDate,
        allowPartialPayment: false,
        paymentInstructions: 'Pay at society office (cash / bank transfer).',
      },
      actor,
    );
    collection = await CollectionModel.findById(created.id);
    if (!collection) {
      throw new Error('Collection create succeeded but document was not found');
    }
    collectionCreated = true;
  }

  const collectionId = String(collection._id);

  const summary = {
    title: COLLECTION_TITLE,
    collectionId,
    collectionNumber: collection.collectionNumber,
    collectionCreated,
    due: dueRaw,
    perFlatRupees: PER_FLAT_RUPEES,
    assignedFlatCount: collection.assignedFlatCount,
    paymentRows: roster.length,
    paid: 0,
    alreadyPaid: 0,
    errors: [] as Array<{ flat: string; error: string }>,
    payments: [] as Array<{
      flat: string;
      method: string;
      amountRupees: number;
      chargeId: string;
      paymentId?: string;
    }>,
  };

  for (const row of roster) {
    const number = flatNumber(row.wing, row.flat);
    try {
      if (row.amountRupees !== PER_FLAT_RUPEES) {
        summary.errors.push({
          flat: number,
          error: `Expected ₹${PER_FLAT_RUPEES}, got ₹${row.amountRupees}`,
        });
        continue;
      }

      const flat = await FlatModel.findOne({ societyId: society._id, number }).select('_id').lean();
      if (!flat) {
        summary.errors.push({ flat: number, error: 'Flat not found' });
        continue;
      }

      const charge = await CollectionChargeModel.findOne({
        societyId: society._id,
        collectionId: collection._id,
        flatId: flat._id,
      });
      if (!charge) {
        summary.errors.push({ flat: number, error: 'Charge not found on collection' });
        continue;
      }

      const paymentMethod = mapMethod(row.method);
      const idempotencyKey = `monarch-chs-${number}-${COLLECTION_TITLE.replace(/\s+/g, '-')}`;

      const paid = await recordOfflineCollectionPayment(
        societyId,
        {
          chargeId: String(charge._id),
          amountPaise,
          paidAt: dueDate,
          paymentMethod,
          referenceNumber: `SEED-CHS-${number}`,
          notes: row.notes ?? `Seeded CHS formation (${row.method})`,
          idempotencyKey,
        },
        actor,
      );

      if (paid.alreadySettled) summary.alreadyPaid += 1;
      else summary.paid += 1;

      summary.payments.push({
        flat: number,
        method: paymentMethod,
        amountRupees: row.amountRupees,
        chargeId: String(charge._id),
        paymentId: paid.paymentId,
      });
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
      summary.errors.push({ flat: number, error: message });
    }
  }

  const refreshed = await CollectionModel.findById(collection._id).lean();
  process.stdout.write(
    `${JSON.stringify(
      {
        ...summary,
        collectedPaise: refreshed?.collectedPaise,
        expectedTotalPaise: refreshed?.expectedTotalPaise,
      },
      null,
      2,
    )}\n`,
  );

  await disconnectDatabase();
}

main().catch(async (error: unknown) => {
  console.error(error);
  await disconnectDatabase().catch(() => undefined);
  process.exit(1);
});
