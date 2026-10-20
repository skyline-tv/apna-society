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
  it('generates monthly bills with due date on the 10th and skips vacant flats', async () => {
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
    expect(res.body.data.createdCount).toBe(2);
    expect(res.body.data.skippedCount).toBe(1);
    expect(res.body.data.totalBilledPaise).toBe(400_000 + 500_000);

    const bill = res.body.data.created.find(
      (b: { monthlyRatePaise: number }) => b.monthlyRatePaise === 400_000,
    );
    expect(bill.dueDate).toBe(new Date('2026-04-10T23:59:59.999+05:30').toISOString());
    expect(bill.ownerUserId).toBe(String(owner._id));
    expect(bill.ownerNameSnapshot).toBeTruthy();
    expect(bill.flatNumberSnapshot).toBeTruthy();
    expect(bill.wingCodeSnapshot).toBe('A');
    expect(bill.status).toBe('ISSUED');

    const audits = await AuditLogModel.countDocuments({
      societyId: ctx.societyId,
      action: 'BILL_GENERATED',
    });
    expect(audits).toBe(2);
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
    expect(first.body.data.createdCount).toBe(1);

    const second = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-05-01', numberOfMonths: 1 });
    expect(second.status).toBe(201);
    expect(second.body.data.createdCount).toBe(0);
    expect(second.body.data.conflictCount).toBe(1);

    const ratesAfter = await FlatModel.find({ societyId: ctx.societyId })
      .select('maintenanceRate number')
      .lean();
    expect(ratesAfter).toHaveLength(140);
    for (const row of ratesBefore) {
      const after = ratesAfter.find((r) => r.number === row.number);
      expect(after?.maintenanceRate).toBe(row.maintenanceRate);
    }
  });

  it('verifies Monarch monthly total when all 140 flats are eligible', async () => {
    const ctx = await createAdminContext(app, 'bill-mon@example.com', 'BILL_MON');
    await seedMonarchLikeSociety(ctx.societyId);
    const owner = await createUser({
      email: 'owner-mon@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });
    await FlatModel.updateMany(
      { societyId: ctx.societyId },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
    );

    const eligible = await request(app)
      .get('/api/v1/admin/billing/eligible-flats')
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(eligible.status).toBe(200);
    expect(eligible.body.data).toHaveLength(140);

    const res = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-06-01T00:00:00.000+05:30', numberOfMonths: 1 });

    expect(res.status).toBe(201);
    expect(res.body.data.createdCount).toBe(140);
    expect(res.body.data.skippedCount).toBe(0);
    // 112×₹4000 + 28×₹5000 = ₹5,88,000 → 58,800,000 paise
    expect(res.body.data.totalBilledPaise).toBe(58_800_000);

    const billCount = await BillModel.countDocuments({ societyId: ctx.societyId });
    expect(billCount).toBe(140);

    const summary = await request(app)
      .get('/api/v1/admin/billing/summary')
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(summary.status).toBe(200);
    expect(summary.body.data.totalBilledPaise).toBe(58_800_000);
  }, 120_000);
});
