import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { BillModel } from '../../src/modules/billing/models/bill.model';
import { calculateSimpleDailyInterestPaise } from '../../src/modules/billing/utils/money';
import { resetEnvCache, loadEnv } from '../../src/config/env';
import { InterestJobRunModel } from '../../src/modules/billing/models/interest-job-run.model';
import {
  ensureSocietyInterestCurrent,
  runInterestAccrualPass,
} from '../../src/modules/billing/services/interest-worker.service';

const app = createApp();

let interestSuite = 0;

async function setupBill() {
  interestSuite += 1;
  const suffix = `${interestSuite}${Date.now().toString(36).slice(-4)}`;
  const ctx = await createAdminContext(app, `int-${suffix}@example.com`, `INT${suffix}`);
  const { flats } = await createWingWithFlats({
    societyId: ctx.societyId,
    code: 'I',
    flatRates: [4000],
  });
  const owner = await createUser({
    email: `owner-int-${suffix}@example.com`,
    roles: ['OWNER'],
    societyId: ctx.societyId,
  });
  await FlatModel.updateOne(
    { _id: flats[0]._id },
    { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
  );

  const gen = await request(app)
    .post('/api/v1/admin/billing/generate')
    .set('Authorization', `Bearer ${ctx.token}`)
    .send({ billingPeriodStart: '2026-04-01T00:00:00.000+05:30', numberOfMonths: 1 });

  const billId = gen.body.data.created[0].id as string;
  return { ctx, owner, billId, flatId: String(flats[0]._id) };
}

describe('Late interest', () => {
  it('charges no interest on or before the 10th and starts on the 11th', async () => {
    const { ctx, billId } = await setupBill();

    const onDue = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: '2026-04-10T23:00:00.000+05:30' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(onDue.status).toBe(200);
    expect(onDue.body.data.overdueDays).toBe(0);
    expect(onDue.body.data.accruedInterestPaise).toBe(0);

    const day11 = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: '2026-04-11T10:00:00.000+05:30' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(day11.body.data.overdueDays).toBe(1);
    expect(day11.body.data.accruedInterestPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 1, 2400),
    );
    expect(day11.body.data.dayCountConvention).toBe('actual/365');
    expect(day11.body.data.rounding).toBe('floor_via_bigint_division');
    expect(day11.body.data.principalEffectiveConvention).toBe(
      'civil_midnight_of_settlement_date',
    );
  });

  it('does not compound and repeated calculation does not duplicate interest', async () => {
    const { ctx, billId } = await setupBill();
    const asOf = '2026-04-20T12:00:00.000+05:30';
    const first = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf })
      .set('Authorization', `Bearer ${ctx.token}`);
    const second = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf })
      .set('Authorization', `Bearer ${ctx.token}`);

    expect(first.body.data.accruedInterestPaise).toBe(second.body.data.accruedInterestPaise);
    const bill = await BillModel.findById(billId).lean();
    expect(bill?.interestAccruedPaise).toBe(first.body.data.accruedInterestPaise);

    const expected = calculateSimpleDailyInterestPaise(400_000, 10, 2400);
    expect(first.body.data.accruedInterestPaise).toBe(expected);
  });

  it('uses ledger segments after partial payment and preserves accrued interest after full pay', async () => {
    process.env.OFFLINE_PAYMENTS_ENABLED = 'true';
    resetEnvCache();
    loadEnv();

    const { ctx, billId } = await setupBill();

    const partial = await request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        billId,
        amountPaise: 100_000,
        paidAt: '2026-04-15T10:00:00.000+05:30',
        referenceNumber: `partial-${billId}`,
        notes: 'Partial',
        idempotencyKey: `partial-${billId}`,
      });
    expect(partial.status).toBe(201);

    const afterPartial = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: '2026-04-16T10:00:00.000+05:30' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(afterPartial.body.data.principalOutstandingPaise).toBe(300_000);
    expect(afterPartial.body.data.accruedInterestPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 4, 2400) +
        calculateSimpleDailyInterestPaise(300_000, 2, 2400),
    );

    const full = await request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        billId,
        amountPaise: 300_000,
        paidAt: '2026-04-16T12:00:00.000+05:30',
        referenceNumber: `full-${billId}`,
        notes: 'Full',
        idempotencyKey: `full-${billId}`,
      });
    expect(full.status).toBe(201);

    const afterFull = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: '2026-04-30T10:00:00.000+05:30' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(afterFull.body.data.principalOutstandingPaise).toBe(0);
    // Prior segments retained; no further accrual after principal hits zero on the 16th.
    expect(afterFull.body.data.accruedInterestPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 4, 2400) +
        calculateSimpleDailyInterestPaise(300_000, 1, 2400),
    );

    process.env.OFFLINE_PAYMENTS_ENABLED = 'false';
    resetEnvCache();
    loadEnv();
  });

  it('daily job accrues overdue interest, is idempotent, and skips paid or not-due bills', async () => {
    process.env.OFFLINE_PAYMENTS_ENABLED = 'true';
    resetEnvCache();
    loadEnv();

    const overdue = await setupBill();
    const paid = await setupBill();
    const notDue = await setupBill();

    const settlePaid = await request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${paid.ctx.token}`)
      .send({
        billId: paid.billId,
        amountPaise: 400_000,
        paidAt: '2026-04-12T10:00:00.000+05:30',
        referenceNumber: `paid-${paid.billId}`,
        notes: 'Full',
        idempotencyKey: `paid-${paid.billId}`,
      });
    expect(settlePaid.status).toBe(201);
    const interestAtPay = calculateSimpleDailyInterestPaise(400_000, 2, 2400);

    const beforeDue = await ensureSocietyInterestCurrent(
      notDue.ctx.societyId,
      new Date('2026-04-10T12:00:00.000+05:30'),
    );
    expect(beforeDue.skipped === true || beforeDue.updated === 0).toBe(true);
    const notDueBill = await BillModel.findById(notDue.billId).lean();
    expect(notDueBill?.interestAccruedPaise).toBe(0);

    const first = await ensureSocietyInterestCurrent(
      overdue.ctx.societyId,
      new Date('2026-04-20T12:00:00.000+05:30'),
    );
    expect(first.skipped).toBe(false);
    expect(first.updated).toBe(1);
    const afterFirst = await BillModel.findById(overdue.billId).lean();
    expect(afterFirst?.interestAccruedPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 10, 2400),
    );
    expect(afterFirst?.status).toBe('OVERDUE');

    const second = await ensureSocietyInterestCurrent(
      overdue.ctx.societyId,
      new Date('2026-04-20T18:00:00.000+05:30'),
    );
    expect(second.skipped).toBe(true);
    expect(second.reason).toBe('already_completed');
    const afterSecond = await BillModel.findById(overdue.billId).lean();
    expect(afterSecond?.interestAccruedPaise).toBe(afterFirst?.interestAccruedPaise);

    const paidPass = await ensureSocietyInterestCurrent(
      paid.ctx.societyId,
      new Date('2026-04-20T12:00:00.000+05:30'),
    );
    expect(paidPass.updated).toBe(0);
    const paidBill = await BillModel.findById(paid.billId).lean();
    expect(paidBill?.status).toBe('PAID');
    expect(paidBill?.interestAccruedPaise).toBe(interestAtPay);

    const missed = await setupBill();
    const catchUp = await ensureSocietyInterestCurrent(
      missed.ctx.societyId,
      new Date('2026-04-25T09:00:00.000+05:30'),
    );
    expect(catchUp.skipped).toBe(false);
    const missedBill = await BillModel.findById(missed.billId).lean();
    expect(missedBill?.interestAccruedPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 15, 2400),
    );

    const concurrent = await Promise.all([
      ensureSocietyInterestCurrent(
        overdue.ctx.societyId,
        new Date('2026-04-20T20:00:00.000+05:30'),
      ),
      ensureSocietyInterestCurrent(
        overdue.ctx.societyId,
        new Date('2026-04-20T20:00:00.000+05:30'),
      ),
    ]);
    expect(concurrent.every((r) => r.skipped)).toBe(true);

    const runs = await InterestJobRunModel.find({ societyId: overdue.ctx.societyId }).lean();
    expect(runs.filter((r) => r.civilDate === '2026-04-20' && r.status === 'COMPLETED')).toHaveLength(
      1,
    );

    const removed = await request(app)
      .post('/api/v1/admin/billing/interest/refresh')
      .set('Authorization', `Bearer ${overdue.ctx.token}`);
    expect(removed.status).toBe(404);

    process.env.OFFLINE_PAYMENTS_ENABLED = 'false';
    resetEnvCache();
    loadEnv();
  });

  it('list and summary refresh interest without opening a bill', async () => {
    const { ctx, billId } = await setupBill();
    const listed = await request(app)
      .get('/api/v1/admin/billing/bills')
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(listed.status).toBe(200);
    const row = listed.body.data.items.find((item: { id: string }) => item.id === billId);
    expect(row.interestAccruedPaise).toBeGreaterThan(0);
    expect(row.totalPayablePaise).toBe(
      row.outstandingPrincipalPaise + row.interestAccruedPaise,
    );

    const summary = await request(app)
      .get('/api/v1/admin/billing/summary')
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(summary.status).toBe(200);
    expect(summary.body.data.totalAccruedInterestPaise).toBe(row.interestAccruedPaise);
    expect(summary.body.data.totalPayablePaise).toBe(
      summary.body.data.totalOutstandingPrincipalPaise +
        summary.body.data.totalAccruedInterestPaise,
    );
  });

  it('opening a bill refreshes stored interest without a manual trigger', async () => {
    const { ctx, billId } = await setupBill();
    const opened = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}`)
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(opened.status).toBe(200);
    expect(opened.body.data.totalPayablePaise).toBe(
      opened.body.data.outstandingPrincipalPaise + opened.body.data.interestAccruedPaise,
    );
    const stored = await BillModel.findById(billId).lean();
    expect(stored?.interestAccruedPaise).toBe(opened.body.data.interestAccruedPaise);
    expect(stored?.interestAccruedPaise).toBeGreaterThan(0);
  });

  it('global worker pass is safe to run twice on the same civil day', async () => {
    const { ctx, billId } = await setupBill();
    const asOf = new Date('2026-04-18T08:00:00.000+05:30');
    const first = await runInterestAccrualPass(asOf);
    expect(first.societiesProcessed).toBeGreaterThanOrEqual(1);
    const afterFirst = await BillModel.findById(billId).lean();
    const expected = calculateSimpleDailyInterestPaise(400_000, 8, 2400);
    expect(afterFirst?.interestAccruedPaise).toBe(expected);

    const second = await runInterestAccrualPass(asOf);
    expect(second.societiesProcessed).toBe(0);
    const afterSecond = await BillModel.findById(billId).lean();
    expect(afterSecond?.interestAccruedPaise).toBe(expected);
  });
});
