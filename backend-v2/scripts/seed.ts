import { loadEnv } from '../src/config/env';
import { connectDatabase, disconnectDatabase } from '../src/database/connection';
import { SocietyModel } from '../src/modules/society/models/society.model';
import { WingModel } from '../src/modules/society/models/wing.model';
import { FlatModel } from '../src/modules/society/models/flat.model';
import { getLogger, resetLogger } from '../src/utils/logger';
import type { FlatType } from '../src/config/constants';

const SOCIETY_CODE = 'MONARCH_SOLITAIRE';
const SOCIETY_NAME = 'Monarch Solitaire A to E';
const WING_CODES = ['A', 'B', 'C', 'D', 'E'] as const;
const FLOORS = 7;
const FLATS_PER_FLOOR = 4;

function maintenanceRate(wingCode: string, position: number): number {
  if (wingCode === 'A') {
    return position <= 2 ? 4000 : 5000;
  }
  if (wingCode === 'E') {
    return position <= 2 ? 5000 : 4000;
  }
  return 4000;
}

function flatTypeForRate(rate: number): FlatType {
  return rate >= 5000 ? '3BHK' : '2BHK';
}

function flatNumber(wingCode: string, floor: number, position: number): string {
  return `${wingCode}-${floor}${position.toString().padStart(2, '0')}`;
}

async function seed(): Promise<void> {
  loadEnv();
  resetLogger();
  const logger = getLogger();
  await connectDatabase();

  let society = await SocietyModel.findOne({ code: SOCIETY_CODE });
  if (!society) {
    society = await SocietyModel.create({
      name: SOCIETY_NAME,
      code: SOCIETY_CODE,
      address: 'Monarch Solitaire',
      city: 'Pune',
      state: 'Maharashtra',
      pincode: '411001',
      isActive: true,
      config: {
        currency: 'INR',
        timezone: 'Asia/Kolkata',
        maintenanceDayOfMonth: 1,
      },
    });
    logger.info({ societyId: society.id }, 'Created society');
  } else {
    // Do not overwrite manually updated society configuration.
    logger.info({ societyId: society.id }, 'Society already exists; leaving config untouched');
  }

  let totalFlats = 0;
  let rate4000 = 0;
  let rate5000 = 0;
  let monthlyTotal = 0;

  for (let i = 0; i < WING_CODES.length; i += 1) {
    const code = WING_CODES[i];
    let wing = await WingModel.findOne({ societyId: society._id, code });
    if (!wing) {
      wing = await WingModel.create({
        societyId: society._id,
        name: `Wing ${code}`,
        code,
        floors: FLOORS,
        flatsPerFloor: FLATS_PER_FLOOR,
        sortOrder: i + 1,
        isActive: true,
      });
      logger.info({ wing: code }, 'Created wing');
    }

    for (let floor = 1; floor <= FLOORS; floor += 1) {
      for (let position = 1; position <= FLATS_PER_FLOOR; position += 1) {
        const number = flatNumber(code, floor, position);
        const rate = maintenanceRate(code, position);
        const type = flatTypeForRate(rate);
        const existing = await FlatModel.findOne({ societyId: society._id, number });
        if (!existing) {
          await FlatModel.create({
            societyId: society._id,
            wingId: wing._id,
            number,
            floor,
            position,
            flatType: type,
            maintenanceRate: rate,
            isActive: true,
            occupancyStatus: 'VACANT',
          });
        } else {
          // Idempotent: never overwrite maintenance rates or core layout fields.
          // Only backfill newly introduced structural fields when missing.
          const patch: Record<string, unknown> = {};
          if (!existing.flatType) patch.flatType = type;
          if (!existing.occupancyStatus) patch.occupancyStatus = 'VACANT';
          if (Object.keys(patch).length > 0) {
            await FlatModel.updateOne({ _id: existing._id }, { $set: patch });
          }
        }
        totalFlats += 1;
        if (rate === 4000) rate4000 += 1;
        if (rate === 5000) rate5000 += 1;
        monthlyTotal += rate;
      }
    }
  }

  const flats = await FlatModel.find({ societyId: society._id }).lean();
  const dbRate4000 = flats.filter((f) => f.maintenanceRate === 4000).length;
  const dbRate5000 = flats.filter((f) => f.maintenanceRate === 5000).length;
  const dbMonthly = flats.reduce((sum, f) => sum + f.maintenanceRate, 0);

  logger.info(
    {
      society: SOCIETY_NAME,
      wings: WING_CODES.length,
      expectedFlats: totalFlats,
      dbFlats: flats.length,
      expectedRate4000: rate4000,
      expectedRate5000: rate5000,
      expectedMonthly: monthlyTotal,
      dbRate4000,
      dbRate5000,
      dbMonthly,
    },
    'Seed complete',
  );

  if (flats.length !== 140 || dbRate4000 !== 112 || dbRate5000 !== 28 || dbMonthly !== 588_000) {
    throw new Error(
      `Seed verification failed: flats=${flats.length}, @4000=${dbRate4000}, @5000=${dbRate5000}, monthly=${dbMonthly}`,
    );
  }

  await disconnectDatabase();
}

seed().catch(async (error: unknown) => {
  console.error(error);
  await disconnectDatabase().catch(() => undefined);
  process.exit(1);
});
