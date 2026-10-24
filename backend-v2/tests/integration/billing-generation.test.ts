import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createUser } from '../helpers/factories';
import {
  createAdminContext,
  createWingWithFlats,
  seedMonarchLikeSociety,
} from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { BillModel } from '../../src/modules/billing/models/bill.model';
import { AuditLogModel } from '../../src/modules/auth/models/audit-log.model';

const app = createApp();

describe('Bill generation', () => {
  it('generates monthly bills for every configured flat including vacant and unassigned', async () => {
    const ctx = await createAdminContext(app, 'bill-gen@example.com', 'BILL_GEN');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'A',
      flatRates: [4000, 5000, 4000],
      occupancyStatuses: ['VACANT', 'VACANT', 'VACANT'],
    });

    const owner = await createUser({
      email: 'owner-bill@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });

    await FlatModel.updateOne(
      { _id: flats[0]._id },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
    );
    await FlatModel.updateOne(
      { _id: flats[1]._id },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
    );
    // flats[2] remains vacant

    const res = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-04-01T00:00:00.000+05:30', numberOfMonths: 1 });

    expect(res.status).toBe(201);
    expect(res.body.data.createdCount).toBe(3);
    expect(res.body.data.skippedCount).toBe(0);
    expect(res.body.data.totalBilledPaise).toBe(400_000 + 500_000 + 400_000);

    const occupied = res.body.data.created.find(
      (b: { monthlyRatePaise: number; ownerUserId?: string }) =>
        b.monthlyRatePaise === 400_000 && b.ownerUserId,
    );
    expect(occupied.dueDate).toBe(new Date('2026-04-10T23:59:59.999+05:30').toISOString());
    expect(occupied.ownerUserId).toBe(String(owner._id));
    expect(occupied.ownerNameSnapshot).toBeTruthy();
    expect(occupied.flatNumberSnapshot).toBeTruthy();
    expect(occupied.wingCodeSnapshot).toBe('A');
    expect(occupied.status).toBe('ISSUED');
    expect(occupied.lineItems[0].type).toBe('MAINTENANCE');

    const vacant = res.body.data.created.find(
      (b: { occupancyStatusSnapshot?: string }) => b.occupancyStatusSnapshot === 'VACANT',
    );
    expect(vacant).toBeTruthy();
    expect(vacant.ownerUserId).toBeUndefined();
    expect(vacant.ownerNameSnapshot).toBe('Unassigned');
    expect(vacant.totalAmountPaise).toBe(400_000);

    const audits = await AuditLogModel.countDocuments({
      societyId: ctx.societyId,
      action: 'BILL_GENERATED',
    });
    expect(audits).toBe(3);
  });

  it('stores the admin-selected due date on every bill in the batch', async () => {
    const ctx = await createAdminContext(app, 'bill-due-15@example.com', 'BILL_DUE15');
    await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'D',
      flatRates: [4000, 5000],
      occupancyStatuses: ['VACANT', 'VACANT'],
    });

    const res = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        billingPeriodStart: '2026-04-01T00:00:00.000+05:30',
        numberOfMonths: 1,
        dueDate: '2026-04-15T00:00:00.000+05:30',
      });

    const expectedDue = new Date('2026-04-15T23:59:59.999+05:30').toISOString();
    expect(res.status).toBe(201);
    expect(res.body.data.createdCount).toBe(2);
    expect(res.body.data.dueDate).toBe(expectedDue);
    expect(res.body.data.created).toHaveLength(2);
    for (const bill of res.body.data.created as Array<{ dueDate: string }>) {
      expect(bill.dueDate).toBe(expectedDue);
    }

    const stored = await BillModel.find({ societyId: ctx.societyId }).lean();
    expect(stored).toHaveLength(2);
    for (const bill of stored) {
      expect(bill.dueDate.toISOString()).toBe(expectedDue);
    }
  });

  it('rejects due dates outside the billing period or that are not valid dates', async () => {
    const ctx = await createAdminContext(app, 'bill-due-bad@example.com', 'BILL_DUEB');
    await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'E',
      flatRates: [4000],
      occupancyStatuses: ['VACANT'],
    });

    const before = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        billingPeriodStart: '2026-04-01T00:00:00.000+05:30',
        numberOfMonths: 1,
        dueDate: '2026-03-31T00:00:00.000+05:30',
      });
    expect(before.status).toBe(400);
    expect(before.body.error.code).toBe('INVALID_DUE_DATE');

    const after = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        billingPeriodStart: '2026-04-01T00:00:00.000+05:30',
        numberOfMonths: 1,
        dueDate: '2026-05-01T00:00:00.000+05:30',
      });
    expect(after.status).toBe(400);
    expect(after.body.error.code).toBe('INVALID_DUE_DATE');

    const invalid = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        billingPeriodStart: '2026-04-01T00:00:00.000+05:30',
        numberOfMonths: 1,
        dueDate: 'not-a-date',
      });
    expect(invalid.status).toBe(400);
    expect(invalid.body.error.code).toBe('VALIDATION_ERROR');

    expect(await BillModel.countDocuments({ societyId: ctx.societyId })).toBe(0);
  });

  it('leaves historical bill due dates unchanged when a later run uses another due date', async () => {
    const ctx = await createAdminContext(app, 'bill-due-hist@example.com', 'BILL_DUEH');
    await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'H',
      flatRates: [4000],
      occupancyStatuses: ['VACANT'],
    });

    const first = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-04-01T00:00:00.000+05:30', numberOfMonths: 1 });
    expect(first.status).toBe(201);
    const historicalDue = first.body.data.created[0].dueDate as string;
    expect(historicalDue).toBe(new Date('2026-04-10T23:59:59.999+05:30').toISOString());
    const historicalId = first.body.data.created[0].id as string;

    const second = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        billingPeriodStart: '2026-05-01T00:00:00.000+05:30',
        numberOfMonths: 1,
        dueDate: '2026-05-15T00:00:00.000+05:30',
      });
    expect(second.status).toBe(201);
    expect(second.body.data.created[0].dueDate).toBe(
      new Date('2026-05-15T23:59:59.999+05:30').toISOString(),
    );

    const historical = await BillModel.findById(historicalId).lean();
    expect(historical?.dueDate.toISOString()).toBe(historicalDue);
  });

  it('bills inactive flats and unassigned flats against the flat id', async () => {
    const ctx = await createAdminContext(app, 'bill-inactive@example.com', 'BILL_INACT');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'Z',
      flatRates: [4000, 5000],
      occupancyStatuses: ['VACANT', 'VACANT'],
    });
    await FlatModel.updateOne({ _id: flats[0]._id }, { isActive: false });

    const res = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-04-01T00:00:00.000+05:30', numberOfMonths: 1 });

    expect(res.status).toBe(201);
    expect(res.body.data.createdCount).toBe(2);
    const inactive = res.body.data.created.find(
      (b: { flatId: string }) => b.flatId === String(flats[0]._id),
    );
    expect(inactive.flatIsActiveSnapshot).toBe(false);
    expect(inactive.ownerAssigned).toBe(false);
    expect(inactive.ownerUserId).toBeUndefined();
  });

  it('generates three-month prepaid bills with accurate calendar end', async () => {
    const ctx = await createAdminContext(app, 'bill-3m@example.com', 'BILL_3M');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'B',
      flatRates: [4000],
    });
    const owner = await createUser({
      email: 'owner-3m@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });
    await FlatModel.updateOne(
      { _id: flats[0]._id },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
    );

    const res = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-01-01T00:00:00.000+05:30', numberOfMonths: 3 });

    expect(res.status).toBe(201);
    expect(res.body.data.createdCount).toBe(1);
    expect(res.body.data.created[0].numberOfMonths).toBe(3);
    expect(res.body.data.created[0].totalAmountPaise).toBe(1_200_000);
    expect(res.body.data.periodEnd).toBe(
      new Date('2026-03-31T23:59:59.999+05:30').toISOString(),
    );
  });

  it('rejects overlapping duplicate billing periods and leaves seed rates unchanged', async () => {
    const ctx = await createAdminContext(app, 'bill-dup@example.com', 'BILL_DUP');
    await seedMonarchLikeSociety(ctx.societyId);
    const ratesBefore = await FlatModel.find({ societyId: ctx.societyId })
      .select('maintenanceRate number')
      .lean();

    const owner = await createUser({
      email: 'owner-dup@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });
    const flat = await FlatModel.findOne({ societyId: ctx.societyId, number: 'A-101' });
    await FlatModel.updateOne(
      { _id: flat!._id },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
    );

    const first = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-05-01', numberOfMonths: 1 });
    expect(first.status).toBe(201);
    expect(first.body.data.createdCount).toBe(140);

    const second = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-05-01', numberOfMonths: 1 });
    expect(second.status).toBe(201);
    expect(second.body.data.createdCount).toBe(0);
    expect(second.body.data.conflictCount).toBe(140);

    const ratesAfter = await FlatModel.find({ societyId: ctx.societyId })
      .select('maintenanceRate number')
      .lean();
    expect(ratesAfter).toHaveLength(140);
    for (const row of ratesBefore) {
      const after = ratesAfter.find((r) => r.number === row.number);
      expect(after?.maintenanceRate).toBe(row.maintenanceRate);
    }
  }, 120_000);

  it('verifies Monarch monthly total for all 140 configured flats without assigning owners', async () => {
    const ctx = await createAdminContext(app, 'bill-mon@example.com', 'BILL_MON');
    await seedMonarchLikeSociety(ctx.societyId);

    const eligible = await request(app)
      .get('/api/v1/admin/billing/eligible-flats')
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(eligible.status).toBe(200);
    expect(eligible.body.data).toHaveLength(140);
    expect(eligible.body.data.every((row: { occupancyStatus: string }) => row.occupancyStatus === 'VACANT')).toBe(
      true,
    );

    const res = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-06-01T00:00:00.000+05:30', numberOfMonths: 1 });

    expect(res.status).toBe(201);
    expect(res.body.data.createdCount).toBe(140);
    expect(res.body.data.skippedCount).toBe(0);
    // Seed: 5 wings × 7 floors × 4 flats, positions 1–2 at ₹4,000 and 3–4 at ₹5,000
    // 70×₹4000 + 70×₹5000 = ₹6,30,000 → 63,000,000 paise
    expect(res.body.data.totalBilledPaise).toBe(63_000_000);

    const billCount = await BillModel.countDocuments({ societyId: ctx.societyId });
    expect(billCount).toBe(140);

    const summary = await request(app)
      .get('/api/v1/admin/billing/summary')
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(summary.status).toBe(200);
    expect(summary.body.data.totalBilledPaise).toBe(63_000_000);
  }, 120_000);
});
