import request from 'supertest';
import type { Express } from 'express';
import { createSociety, createUser } from './factories';
import { loginExistingUser } from './auth-login';
import { WingModel } from '../../src/modules/society/models/wing.model';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import type { FlatType, OccupancyStatus } from '../../src/config/constants';

export async function loginAsAdmin(app: Express, email: string, societyId: string) {
  const user = await createUser({ email, roles: ['ADMIN'], societyId });
  const { token } = await loginExistingUser(app, user.mobileE164!);
  return {
    token,
    societyId,
    userId: String(user._id),
  };
}

export async function createAdminContext(app: Express, email: string, societyCode: string) {
  const society = await createSociety(societyCode);
  const auth = await loginAsAdmin(app, email, String(society._id));
  return { society, ...auth };
}

export async function createWingWithFlats(input: {
  societyId: string;
  code: string;
  name?: string;
  floors?: number;
  flatsPerFloor?: number;
  sortOrder?: number;
  flatRates?: number[];
  occupancyStatuses?: OccupancyStatus[];
  flatTypes?: FlatType[];
}) {
  const wing = await WingModel.create({
    societyId: input.societyId,
    name: input.name ?? `Wing ${input.code}`,
    code: input.code,
    floors: input.floors ?? 7,
    flatsPerFloor: input.flatsPerFloor ?? 4,
    sortOrder: input.sortOrder ?? 1,
    isActive: true,
  });

  const rates = input.flatRates ?? [4000, 4000, 5000, 5000];
  const flats = [];
  for (let i = 0; i < rates.length; i += 1) {
    const position = (i % 4) + 1;
    const floor = Math.floor(i / 4) + 1;
    const rate = rates[i];
    const flat = await FlatModel.create({
      societyId: input.societyId,
      wingId: wing._id,
      number: `${input.code}-${floor}${String(position).padStart(2, '0')}`,
      floor,
      position,
      flatType: input.flatTypes?.[i] ?? (rate >= 5000 ? '3BHK' : '2BHK'),
      maintenanceRate: rate,
      isActive: true,
      occupancyStatus: input.occupancyStatuses?.[i] ?? 'VACANT',
    });
    flats.push(flat);
  }

  return { wing, flats };
}

export async function seedMonarchLikeSociety(societyId: string) {
  const wingCodes = ['A', 'B', 'C', 'D', 'E'] as const;
  for (let w = 0; w < wingCodes.length; w += 1) {
    const code = wingCodes[w];
    const wing = await WingModel.create({
      societyId,
      name: `Wing ${code}`,
      code,
      floors: 7,
      flatsPerFloor: 4,
      sortOrder: w + 1,
      isActive: true,
    });

    for (let floor = 1; floor <= 7; floor += 1) {
      for (let position = 1; position <= 4; position += 1) {
        let rate = 4000;
        if (code === 'A') rate = position <= 2 ? 4000 : 5000;
        if (code === 'E') rate = position <= 2 ? 5000 : 4000;
        await FlatModel.create({
          societyId,
          wingId: wing._id,
          number: `${code}-${floor}${String(position).padStart(2, '0')}`,
          floor,
          position,
          flatType: rate >= 5000 ? '3BHK' : '2BHK',
          maintenanceRate: rate,
          isActive: true,
          occupancyStatus: 'VACANT',
        });
      }
    }
  }
}
