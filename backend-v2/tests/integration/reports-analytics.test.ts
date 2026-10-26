import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginByEmail } from '../helpers/auth-login';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { BillModel } from '../../src/modules/billing/models/bill.model';
import { ComplaintModel } from '../../src/modules/complaints/models/complaint.model';
import { resetEnvCache, loadEnv } from '../../src/config/env';

const app = createApp();

async function login(email: string) {
  const { token } = await loginByEmail(app, email);
  return token;
}

async function setupSociety(prefix: string) {
  const ctx = await createAdminContext(app, `${prefix}-admin@example.com`, prefix.toUpperCase());
  const wingA = await createWingWithFlats({
    societyId: ctx.societyId,
    code: 'A',
    flatRates: [4000, 5000],
  });
  const wingB = await createWingWithFlats({
    societyId: ctx.societyId,
    code: 'B',
    flatRates: [3000],
  });
  const ownerA = await createUser({
    email: `${prefix}-ownera@example.com`,
    roles: ['OWNER'],
    societyId: ctx.societyId,
  });
  const ownerB = await createUser({
    email: `${prefix}-ownerb@example.com`,
    roles: ['OWNER'],
    societyId: ctx.societyId,
  });
  const ownerC = await createUser({
    email: `${prefix}-ownerc@example.com`,
    roles: ['OWNER'],
    societyId: ctx.societyId,
  });

  await FlatModel.updateOne(
    { _id: wingA.flats[0]._id },
    { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: ownerA._id },
  );
  await FlatModel.updateOne(
    { _id: wingA.flats[1]._id },
    { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: ownerB._id },
  );
  await FlatModel.updateOne(
    { _id: wingB.flats[0]._id },
    { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: ownerC._id },
  );

  const gen = await request(app)
    .post('/api/v1/admin/billing/generate')
    .set('Authorization', `Bearer ${ctx.token}`)
    .send({ billingPeriodStart: '2026-08-01T00:00:00.000+05:30', numberOfMonths: 1 });
  expect(gen.status).toBe(201);
  expect(gen.body.data.createdCount).toBe(3);

  process.env.OFFLINE_PAYMENTS_ENABLED = 'true';
  resetEnvCache();
  loadEnv();

  const billA1 = gen.body.data.created.find(
    (b: { flatId: string }) => b.flatId === String(wingA.flats[0]._id),
  );
  // Partial offline payment on first bill (half of 400000)
  const offline = await request(app)
    .post('/api/v1/admin/payments/offline')
    .set('Authorization', `Bearer ${ctx.token}`)
    .send({
      billId: billA1.id,
      amountPaise: 200_000,
      paidAt: '2026-08-15T10:00:00.000Z',
      referenceNumber: `${prefix}-off-1`,
      idempotencyKey: `${prefix}-off-1`,
    });
  expect(offline.status).toBe(201);

  const other = await createAdminContext(
    app,
    `${prefix}-other-admin@example.com`,
    `${prefix}OTH`,
  );

  return {
    ctx,
    other,
    wingA,
    wingB,
    ownerA,
    ownerToken: await login(`${prefix}-ownera@example.com`),
    billA1Id: billA1.id as string,
    flatA1: String(wingA.flats[0]._id),
  };
}

describe('Reports authorization and isolation', () => {
  it('blocks owners/tenants/guards and cross-society access', async () => {
    const setup = await setupSociety('riso');
    const ownerDenied = await request(app)
      .get('/api/v1/admin/reports/financial')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(ownerDenied.status).toBe(403);

    const cross = await request(app)
      .get('/api/v1/admin/reports/financial')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .set('x-society-id', setup.other.societyId);
    expect(cross.status).toBe(403);
  });
});

describe('Financial and collection reports', () => {
  it('reports billed/collected/outstanding, online/offline, wing filter, empty ranges', async () => {
    const setup = await setupSociety('rfin');

    const financial = await request(app)
      .get('/api/v1/admin/reports/financial')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .query({
        from: '2026-07-01T00:00:00.000Z',
        to: '2026-09-30T23:59:59.000Z',
      });
    expect(financial.status).toBe(200);
    // 4000+5000+3000 = 12000 INR = 1_200_000 paise
    expect(financial.body.data.totalBilledPaise).toBe(1_200_000);
    expect(financial.body.data.totalCollectedPaise).toBe(200_000);
    expect(financial.body.data.totalOutstandingPrincipalPaise).toBe(1_000_000);
    expect(financial.body.data.totalOfflineCollectionsPaise).toBe(200_000);
    expect(financial.body.data.totalOnlineCollectionsPaise).toBe(0);
    expect(financial.body.data.paymentSuccessCount).toBe(1);
    expect(financial.body.data.collectionPercentage).toBeCloseTo(16.66, 1);
    expect(financial.body.data.monthly.length).toBeGreaterThanOrEqual(1);
    expect(financial.body.data.yearly.length).toBeGreaterThanOrEqual(1);

    const wingA = await request(app)
      .get('/api/v1/admin/reports/collections')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .query({
        from: '2026-07-01T00:00:00.000Z',
        to: '2026-09-30T23:59:59.000Z',
        wingCode: 'A',
      });
    expect(wingA.status).toBe(200);
    expect(wingA.body.data.totalBilledPaise).toBe(900_000);
    expect(wingA.body.data.wingWise.every((w: { wingCode: string }) => w.wingCode === 'A')).toBe(
      true,
    );

    // Historical snapshot: mutate live flat rate — reports must keep bill snapshot totals
    await FlatModel.updateOne({ _id: setup.flatA1 }, { maintenanceRate: 99999 });
    const afterRateChange = await request(app)
      .get('/api/v1/admin/reports/financial')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .query({
        from: '2026-07-01T00:00:00.000Z',
        to: '2026-09-30T23:59:59.000Z',
        flatId: setup.flatA1,
      });
    expect(afterRateChange.body.data.totalBilledPaise).toBe(400_000);

    const empty = await request(app)
      .get('/api/v1/admin/reports/financial')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .query({
        from: '2020-01-01T00:00:00.000Z',
        to: '2020-01-31T00:00:00.000Z',
      });
    expect(empty.status).toBe(200);
    expect(empty.body.data.totalBilledPaise).toBe(0);
    expect(empty.body.data.collectionPercentage).toBe(0);

    const tooWide = await request(app)
      .get('/api/v1/admin/reports/financial')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .query({
        from: '2020-01-01T00:00:00.000Z',
        to: '2026-01-01T00:00:00.000Z',
      });
    expect(tooWide.status).toBe(400);
  });

  it('paginates outstanding and streams CSV with formula injection protection', async () => {
    const setup = await setupSociety('rcsv');

    // Inject formula-like owner name on a bill snapshot
    await BillModel.updateOne(
      { _id: setup.billA1Id },
      { ownerNameSnapshot: '=1+1' },
    );

    const outstanding = await request(app)
      .get('/api/v1/admin/reports/outstanding')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .query({
        from: '2026-07-01T00:00:00.000Z',
        to: '2026-09-30T23:59:59.000Z',
        page: 1,
        limit: 2,
      });
    expect(outstanding.status).toBe(200);
    expect(outstanding.body.data.items.length).toBeLessThanOrEqual(2);
    expect(outstanding.body.data.pagination.total).toBeGreaterThanOrEqual(2);

    const csv = await request(app)
      .get('/api/v1/admin/reports/export/financial')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .query({
        from: '2026-07-01T00:00:00.000Z',
        to: '2026-09-30T23:59:59.000Z',
        format: 'csv',
      });
    expect(csv.status).toBe(200);
    expect(csv.headers['content-type']).toContain('text/csv');
    expect(csv.text).toContain('billNumber,wingCode,flatNumber');
    expect(csv.text).toContain('billingPeriodStart');
    expect(csv.text).toContain("'=1+1");
    expect(csv.text).toContain('4000.00');

    const paymentsCsv = await request(app)
      .get('/api/v1/admin/reports/export/payments')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .query({
        from: '2026-07-01T00:00:00.000Z',
        to: '2026-09-30T23:59:59.000Z',
      });
    expect(paymentsCsv.status).toBe(200);
    expect(paymentsCsv.text).toContain('paymentNumber,status,paymentMethod');
    expect(paymentsCsv.text).toContain('CASH');
  });
});

describe('Complaint analytics and dashboard', () => {
  it('aggregates complaint statuses and dashboard overview', async () => {
    const setup = await setupSociety('rcmp');

    const open = await ComplaintModel.create({
      societyId: setup.ctx.societyId,
      flatId: setup.flatA1,
      complaintNumber: 'CMP-RPT-1',
      raisedByUserId: setup.ownerA._id,
      raisedByRole: 'OWNER',
      category: 'PLUMBING',
      title: 'Leak',
      description: 'Kitchen sink leak needs attention',
      priority: 'HIGH',
      status: 'OPEN',
    });
    const resolved = await ComplaintModel.create({
      societyId: setup.ctx.societyId,
      flatId: setup.flatA1,
      complaintNumber: 'CMP-RPT-2',
      raisedByUserId: setup.ownerA._id,
      raisedByRole: 'OWNER',
      category: 'ELECTRICAL',
      title: 'Socket',
      description: 'Living room socket not working',
      priority: 'MEDIUM',
      status: 'RESOLVED',
      resolvedAt: new Date('2026-08-10T12:00:00.000Z'),
    });
    await ComplaintModel.collection.updateOne(
      { _id: open._id },
      { $set: { createdAt: new Date('2026-08-05T12:00:00.000Z') } },
    );
    await ComplaintModel.collection.updateOne(
      { _id: resolved._id },
      { $set: { createdAt: new Date('2026-08-08T12:00:00.000Z') } },
    );

    const analytics = await request(app)
      .get('/api/v1/admin/reports/complaints')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .query({
        from: '2026-07-01T00:00:00.000Z',
        to: '2026-09-30T23:59:59.000Z',
      });
    expect(analytics.status).toBe(200);
    expect(analytics.body.data.totalComplaints).toBeGreaterThanOrEqual(2);
    expect(analytics.body.data.open).toBeGreaterThanOrEqual(1);
    expect(analytics.body.data.resolved).toBeGreaterThanOrEqual(1);
    expect(analytics.body.data.byCategory.PLUMBING).toBeGreaterThanOrEqual(1);
    expect(analytics.body.data.averageResolutionHours).not.toBeNull();

    const dashboard = await request(app)
      .get('/api/v1/admin/reports/dashboard')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .query({
        from: '2026-07-01T00:00:00.000Z',
        to: '2026-09-30T23:59:59.000Z',
      });
    expect(dashboard.status).toBe(200);
    expect(dashboard.body.data.financial.totalBilledPaise).toBe(1_200_000);
    expect(dashboard.body.data.complaints.totalComplaints).toBeGreaterThanOrEqual(2);

    const complaintsCsv = await request(app)
      .get('/api/v1/admin/reports/export/complaints')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .query({
        from: '2026-07-01T00:00:00.000Z',
        to: '2026-09-30T23:59:59.000Z',
      });
    expect(complaintsCsv.status).toBe(200);
    expect(complaintsCsv.text).toContain('complaintNumber,status,category');
  });
});
