import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginAs as loginAsHelper } from '../helpers/auth-login';
import { createSociety, createUser } from '../helpers/factories';
import {
  createAdminContext,
  createWingWithFlats,
  loginAsAdmin,
  seedMonarchLikeSociety,
} from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { SocietyModel } from '../../src/modules/society/models/society.model';
import { WingModel } from '../../src/modules/society/models/wing.model';

const app = createApp();

async function ownerToken(email: string, societyId: string) {
  const { token } = await loginAsHelper(app, email, ['OWNER'], societyId);
  return token;
}

describe('Admin society management', () => {
  it('allows admin to view society', async () => {
    const ctx = await createAdminContext(app, 'soc-view@example.com', 'SOC_VIEW');
    const res = await request(app)
      .get('/api/v1/admin/society')
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(res.status).toBe(200);
    expect(res.body.data.code).toBe('SOC_VIEW');
    expect(res.body.data.timezone).toBe('Asia/Kolkata');
    expect(res.body.data).not.toHaveProperty('_id');
    expect(res.body.data).not.toHaveProperty('__v');
  });

  it('allows admin to update allowed society fields', async () => {
    const ctx = await createAdminContext(app, 'soc-upd@example.com', 'SOC_UPD');
    const res = await request(app)
      .patch('/api/v1/admin/society')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'Updated Society',
        city: 'Pune',
        contactEmail: 'office@example.com',
        timezone: 'Asia/Kolkata',
      });
    expect(res.status).toBe(200);
    expect(res.body.data.name).toBe('Updated Society');
    expect(res.body.data.city).toBe('Pune');
    expect(res.body.data.code).toBe('SOC_UPD');

    const db = await SocietyModel.findById(ctx.societyId).lean();
    expect(db?.code).toBe('SOC_UPD');
    expect(db?.name).toBe('Updated Society');
  });

  it('blocks non-admin from updating society', async () => {
    const society = await createSociety('SOC_OWNER');
    const token = await ownerToken('owner-soc@example.com', String(society._id));
    const res = await request(app)
      .patch('/api/v1/admin/society')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Nope' });
    expect(res.status).toBe(403);
  });

  it('enforces cross-society isolation via x-society-id', async () => {
    const societyA = await createSociety('ISO_ADM_A');
    const societyB = await createSociety('ISO_ADM_B');
    const auth = await loginAsAdmin(app, 'iso-adm@example.com', String(societyA._id));

    const denied = await request(app)
      .get('/api/v1/admin/society')
      .set('Authorization', `Bearer ${auth.token}`)
      .set('x-society-id', String(societyB._id));
    expect(denied.status).toBe(403);
    expect(denied.body.error.code).toBe('SOCIETY_ISOLATION');
  });
});

describe('Admin wing management', () => {
  it('lists wings with flat counts', async () => {
    const ctx = await createAdminContext(app, 'wing-list@example.com', 'WING_LIST');
    await createWingWithFlats({ societyId: ctx.societyId, code: 'A', flatRates: [4000, 4000] });
    const res = await request(app)
      .get('/api/v1/admin/wings')
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].flatCount).toBe(2);
  });

  it('creates a wing', async () => {
    const ctx = await createAdminContext(app, 'wing-create@example.com', 'WING_CREATE');
    const res = await request(app)
      .post('/api/v1/admin/wings')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ name: 'Wing F', code: 'F', floors: 7, flatsPerFloor: 4 });
    expect(res.status).toBe(201);
    expect(res.body.data.code).toBe('F');
    expect(res.body.data.flatCount).toBe(0);
  });

  it('rejects duplicate wing codes', async () => {
    const ctx = await createAdminContext(app, 'wing-dup@example.com', 'WING_DUP');
    await WingModel.create({
      societyId: ctx.societyId,
      name: 'Wing A',
      code: 'A',
      floors: 7,
      flatsPerFloor: 4,
      sortOrder: 1,
    });

    const res = await request(app)
      .post('/api/v1/admin/wings')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ name: 'Wing A2', code: 'A' });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('DUPLICATE_WING_CODE');
  });

  it('updates a wing', async () => {
    const ctx = await createAdminContext(app, 'wing-upd@example.com', 'WING_UPD');
    const { wing } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'B',
      flatRates: [4000],
    });
    const res = await request(app)
      .patch(`/api/v1/admin/wings/${wing._id}`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ name: 'Wing B Renamed', sortOrder: 9 });
    expect(res.status).toBe(200);
    expect(res.body.data.name).toBe('Wing B Renamed');
    expect(res.body.data.flatCount).toBe(1);
  });

  it('prevents cross-society wing access', async () => {
    const a = await createAdminContext(app, 'wing-iso-a@example.com', 'WING_ISO_A');
    const b = await createAdminContext(app, 'wing-iso-b@example.com', 'WING_ISO_B');
    const { wing } = await createWingWithFlats({
      societyId: b.societyId,
      code: 'Z',
      flatRates: [4000],
    });

    const res = await request(app)
      .get(`/api/v1/admin/wings/${wing._id}`)
      .set('Authorization', `Bearer ${a.token}`);
    expect(res.status).toBe(404);
  });
});

describe('Admin flat management', () => {
  it('lists, filters, searches and paginates flats', async () => {
    const ctx = await createAdminContext(app, 'flat-list@example.com', 'FLAT_LIST');
    const { wing, flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'A',
      flatRates: [4000, 4000, 5000, 5000],
      occupancyStatuses: ['VACANT', 'OWNER_OCCUPIED', 'VACANT', 'TENANT_OCCUPIED'],
    });

    const byWing = await request(app)
      .get('/api/v1/admin/flats')
      .query({ wingId: String(wing._id) })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(byWing.status).toBe(200);
    expect(byWing.body.data.items).toHaveLength(4);

    const byFloor = await request(app)
      .get('/api/v1/admin/flats')
      .query({ floor: 1 })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(byFloor.body.data.items).toHaveLength(4);

    const byOcc = await request(app)
      .get('/api/v1/admin/flats')
      .query({ occupancyStatus: 'OWNER_OCCUPIED' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(byOcc.body.data.items).toHaveLength(1);

    const search = await request(app)
      .get('/api/v1/admin/flats')
      .query({ search: flats[0].number })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(search.body.data.items).toHaveLength(1);

    const page = await request(app)
      .get('/api/v1/admin/flats')
      .query({ page: 1, limit: 2, sortBy: 'number', sortOrder: 'asc' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(page.body.data.items).toHaveLength(2);
    expect(page.body.data.pagination.total).toBe(4);
    expect(page.body.data.pagination.totalPages).toBe(2);
  });

  it('creates a flat and rejects duplicates / invalid wing', async () => {
    const ctx = await createAdminContext(app, 'flat-create@example.com', 'FLAT_CREATE');
    const { wing } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'C',
      flatRates: [4000],
    });

    const created = await request(app)
      .post('/api/v1/admin/flats')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        wingId: String(wing._id),
        number: 'C-201',
        floor: 2,
        position: 1,
        flatType: '2BHK',
        maintenanceRate: 4000,
      });
    expect(created.status).toBe(201);
    expect(created.body.data.number).toBe('C-201');

    const dup = await request(app)
      .post('/api/v1/admin/flats')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        wingId: String(wing._id),
        number: 'C-201',
        floor: 2,
        position: 2,
        flatType: '2BHK',
        maintenanceRate: 4000,
      });
    expect(dup.status).toBe(409);

    const otherSociety = await createSociety('FLAT_BAD_WING');
    const foreignWing = await WingModel.create({
      societyId: otherSociety._id,
      name: 'Foreign',
      code: 'X',
      floors: 7,
      flatsPerFloor: 4,
      sortOrder: 1,
    });
    const invalidWing = await request(app)
      .post('/api/v1/admin/flats')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        wingId: String(foreignWing._id),
        number: 'X-101',
        floor: 1,
        position: 1,
        flatType: '2BHK',
        maintenanceRate: 4000,
      });
    expect(invalidWing.status).toBe(404);
  });

  it('updates flat details and enforces deactivation safeguards', async () => {
    const ctx = await createAdminContext(app, 'flat-upd@example.com', 'FLAT_UPD');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'D',
      flatRates: [4000],
      occupancyStatuses: ['OWNER_OCCUPIED'],
    });
    const flatId = String(flats[0]._id);

    const updated = await request(app)
      .patch(`/api/v1/admin/flats/${flatId}`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ notes: 'Corner flat', parking: { hasParking: true, slotLabel: 'P-1' } });
    expect(updated.status).toBe(200);
    expect(updated.body.data.notes).toBe('Corner flat');
    expect(updated.body.data.parking.slotLabel).toBe('P-1');

    const blocked = await request(app)
      .patch(`/api/v1/admin/flats/${flatId}`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ isActive: false });
    expect(blocked.status).toBe(403);
    expect(blocked.body.error.code).toBe('FLAT_DEACTIVATE_BLOCKED');

    const forced = await request(app)
      .patch(`/api/v1/admin/flats/${flatId}`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        isActive: false,
        forceDeactivate: true,
        deactivationReason: 'Administrative correction',
      });
    expect(forced.status).toBe(200);
    expect(forced.body.data.isActive).toBe(false);
  });

  it('prevents cross-society flat access', async () => {
    const a = await createAdminContext(app, 'flat-iso-a@example.com', 'FLAT_ISO_A');
    const b = await createAdminContext(app, 'flat-iso-b@example.com', 'FLAT_ISO_B');
    const { flats } = await createWingWithFlats({
      societyId: b.societyId,
      code: 'E',
      flatRates: [4000],
    });
    const res = await request(app)
      .get(`/api/v1/admin/flats/${flats[0]._id}`)
      .set('Authorization', `Bearer ${a.token}`);
    expect(res.status).toBe(404);
  });
});

describe('Admin dashboard and preservation', () => {
  it('returns database-derived dashboard statistics', async () => {
    const ctx = await createAdminContext(app, 'dash@example.com', 'DASH_SOC');
    await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'A',
      sortOrder: 1,
      flatRates: [4000, 5000],
      occupancyStatuses: ['OWNER_OCCUPIED', 'TENANT_OCCUPIED'],
      flatTypes: ['2BHK', '3BHK'],
    });
    await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'B',
      sortOrder: 2,
      flatRates: [4000, 4000],
      occupancyStatuses: ['VACANT', 'VACANT'],
      flatTypes: ['2BHK', '2BHK'],
    });

    const res = await request(app)
      .get('/api/v1/admin/dashboard')
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(res.status).toBe(200);
    expect(res.body.data.totals.wings).toBe(2);
    expect(res.body.data.totals.flats).toBe(4);
    expect(res.body.data.totals.activeFlats).toBe(4);
    expect(res.body.data.totals.ownerOccupiedFlats).toBe(1);
    expect(res.body.data.totals.tenantOccupiedFlats).toBe(1);
    expect(res.body.data.totals.vacantFlats).toBe(2);
    expect(res.body.data.totals.twoBhkCount).toBe(3);
    expect(res.body.data.totals.threeBhkCount).toBe(1);
    expect(res.body.data.totals.monthlyMaintenanceTotal).toBe(17_000);
    expect(res.body.data.wings).toHaveLength(2);
  });

  it('preserves monarch 140 flats and rates when society config is updated', async () => {
    const ctx = await createAdminContext(app, 'preserve@example.com', 'MONARCH_TEST');
    await seedMonarchLikeSociety(ctx.societyId);

    const before = await FlatModel.find({ societyId: ctx.societyId }).lean();
    expect(before).toHaveLength(140);
    const beforeRates = before.map((f) => `${f.number}:${f.maintenanceRate}`).sort();

    const sample = before[0];
    await FlatModel.updateOne({ _id: sample._id }, { $set: { notes: 'manual note' } });

    await request(app)
      .patch('/api/v1/admin/society')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ city: 'Pune', contactPhone: '9999999999' });

    // Idempotent seed path: existing flat rates/config must not be overwritten.
    for (const flat of before) {
      await FlatModel.updateOne(
        { _id: flat._id },
        {
          $set: {
            ...(flat.flatType ? {} : { flatType: flat.maintenanceRate >= 5000 ? '3BHK' : '2BHK' }),
          },
        },
      );
    }

    const after = await FlatModel.find({ societyId: ctx.societyId }).lean();
    expect(after).toHaveLength(140);
    const afterRates = after.map((f) => `${f.number}:${f.maintenanceRate}`).sort();
    expect(afterRates).toEqual(beforeRates);

    const rate4000 = after.filter((f) => f.maintenanceRate === 4000).length;
    const rate5000 = after.filter((f) => f.maintenanceRate === 5000).length;
    const monthly = after.reduce((sum, f) => sum + f.maintenanceRate, 0);
    expect(rate4000).toBe(112);
    expect(rate5000).toBe(28);
    expect(monthly).toBe(588_000);

    const dash = await request(app)
      .get('/api/v1/admin/dashboard')
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(dash.body.data.totals.flats).toBe(140);
    expect(dash.body.data.totals.monthlyMaintenanceTotal).toBe(588_000);
    expect(dash.body.data.totals.wings).toBe(5);

    const touched = await FlatModel.findById(sample._id).lean();
    expect(touched?.notes).toBe('manual note');
  });
});
