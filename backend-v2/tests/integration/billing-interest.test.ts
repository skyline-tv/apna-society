import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { loginByEmail } from '../helpers/auth-login';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { BillModel } from '../../src/modules/billing/models/bill.model';
import { PaymentModel } from '../../src/modules/billing/models/payment.model';
import { calculateSimpleDailyInterestPaise } from '../../src/modules/billing/utils/money';
import { resetEnvCache, loadEnv } from '../../src/config/env';
import { InterestJobRunModel } from '../../src/modules/billing/models/interest-job-run.model';
import {
  ensureSocietyInterestCurrent,
  runInterestAccrualPass,
} from '../../src/modules/billing/services/interest-worker.service';
import { amountDuePaise } from '../../src/modules/billing/services/payment.service';

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
    expect(paidBill?.outstandingPrincipalPaise).toBe(0);
    // Principal-only settlement leaves unpaid interest outstanding; interest on
    // principal stops because principal is zero, but the bill is not PAID until
    // remaining interest is collected.
    expect(paidBill?.status).not.toBe('PAID');
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

describe('Interest included at payment time', () => {
  beforeEach(() => {
    process.env.OFFLINE_PAYMENTS_ENABLED = 'true';
    resetEnvCache();
    loadEnv();
  });

  afterEach(() => {
    process.env.OFFLINE_PAYMENTS_ENABLED = 'false';
    resetEnvCache();
    loadEnv();
  });

  async function recordOffline(
    token: string,
    body: {
      billId: string;
      amountPaise: number;
      paidAt: string;
      referenceNumber: string;
      notes?: string;
      idempotencyKey?: string;
    },
  ) {
    return request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${token}`)
      .send(body);
  }

  it('charges no overdue interest when payment is on or before the 10th', async () => {
    const { ctx, billId } = await setupBill();
    const paid = await recordOffline(ctx.token, {
      billId,
      amountPaise: 400_000,
      paidAt: '2026-04-10T18:00:00.000+05:30',
      referenceNumber: `ontime-${billId}`,
      idempotencyKey: `ontime-${billId}`,
    });
    expect(paid.status).toBe(201);

    const payment = await PaymentModel.findById(paid.body.data.paymentId).lean();
    expect(payment?.allocatedToPrincipalPaise).toBe(400_000);
    expect(payment?.allocatedToInterestPaise).toBe(0);

    const bill = await BillModel.findById(billId).lean();
    expect(bill?.outstandingPrincipalPaise).toBe(0);
    expect(bill?.interestAccruedPaise).toBe(0);
    expect(bill?.status).toBe('PAID');
  });

  it('starts interest on the 11th and includes it in the payment allocation', async () => {
    const { ctx, billId } = await setupBill();
    const interest = calculateSimpleDailyInterestPaise(400_000, 1, 2400);
    expect(interest).toBeGreaterThan(0);

    const paid = await recordOffline(ctx.token, {
      billId,
      amountPaise: amountDuePaise(400_000, interest),
      paidAt: '2026-04-11T10:00:00.000+05:30',
      referenceNumber: `day11-${billId}`,
      idempotencyKey: `day11-${billId}`,
    });
    expect(paid.status).toBe(201);

    const payment = await PaymentModel.findById(paid.body.data.paymentId).lean();
    expect(payment?.allocatedToPrincipalPaise).toBe(400_000);
    expect(payment?.allocatedToInterestPaise).toBe(interest);

    const bill = await BillModel.findById(billId).lean();
    expect(bill?.outstandingPrincipalPaise).toBe(0);
    expect(bill?.interestAccruedPaise).toBe(interest);
    expect(bill?.amountPaidPaise).toBe(400_000);
    expect(bill?.status).toBe('PAID');
  });

  it('includes multi-day accrued interest in the amount due', async () => {
    const { ctx, billId } = await setupBill();
    const interest = calculateSimpleDailyInterestPaise(400_000, 10, 2400);

    const paid = await recordOffline(ctx.token, {
      billId,
      amountPaise: amountDuePaise(400_000, interest),
      paidAt: '2026-04-20T12:00:00.000+05:30',
      referenceNumber: `overdue-${billId}`,
      idempotencyKey: `overdue-${billId}`,
    });
    expect(paid.status).toBe(201);

    const payment = await PaymentModel.findById(paid.body.data.paymentId).lean();
    expect(payment?.amountPaise).toBe(400_000 + interest);
    expect(payment?.allocatedToPrincipalPaise).toBe(400_000);
    expect(payment?.allocatedToInterestPaise).toBe(interest);

    const bill = await BillModel.findById(billId).lean();
    expect(bill?.outstandingPrincipalPaise).toBe(0);
    expect(bill?.interestAccruedPaise).toBe(interest);
    expect(bill?.status).toBe('PAID');
  });

  it('continues accruing on remaining principal after a partial payment', async () => {
    const { ctx, billId } = await setupBill();

    const partial = await recordOffline(ctx.token, {
      billId,
      amountPaise: 100_000,
      paidAt: '2026-04-15T10:00:00.000+05:30',
      referenceNumber: `part-pay-${billId}`,
      idempotencyKey: `part-pay-${billId}`,
    });
    expect(partial.status).toBe(201);

    const payment = await PaymentModel.findById(partial.body.data.paymentId).lean();
    expect(payment?.allocatedToPrincipalPaise).toBe(100_000);
    expect(payment?.allocatedToInterestPaise).toBe(0);

    const after = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: '2026-04-25T10:00:00.000+05:30' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(after.body.data.principalOutstandingPaise).toBe(300_000);
    expect(after.body.data.accruedInterestPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 4, 2400) +
        calculateSimpleDailyInterestPaise(300_000, 11, 2400),
    );
  });

  it('stops future principal interest after full principal settlement', async () => {
    const { ctx, billId } = await setupBill();
    // Settlement is effective at civil midnight, so the payment day itself uses
    // the reduced principal (here zero) and does not accrue another day.
    const interestThroughPaymentDay = calculateSimpleDailyInterestPaise(400_000, 10, 2400);
    const interestAfterSettlement = calculateSimpleDailyInterestPaise(400_000, 9, 2400);

    const paid = await recordOffline(ctx.token, {
      billId,
      amountPaise: amountDuePaise(400_000, interestThroughPaymentDay),
      paidAt: '2026-04-20T09:00:00.000+05:30',
      referenceNumber: `settled-${billId}`,
      idempotencyKey: `settled-${billId}`,
    });
    expect(paid.status).toBe(201);

    const later = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: '2026-05-15T10:00:00.000+05:30' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(later.body.data.principalOutstandingPaise).toBe(0);
    expect(later.body.data.accruedInterestPaise).toBe(interestAfterSettlement);
  });

  it('never compounds interest into principal', async () => {
    const { ctx, billId } = await setupBill();
    const interestThroughPaymentDay = calculateSimpleDailyInterestPaise(400_000, 5, 2400);
    const simpleInterestAfterSettlement = calculateSimpleDailyInterestPaise(400_000, 4, 2400);

    const paid = await recordOffline(ctx.token, {
      billId,
      amountPaise: amountDuePaise(400_000, interestThroughPaymentDay),
      paidAt: '2026-04-15T12:00:00.000+05:30',
      referenceNumber: `simple-${billId}`,
      idempotencyKey: `simple-${billId}`,
    });
    expect(paid.status).toBe(201);

    const payment = await PaymentModel.findById(paid.body.data.paymentId).lean();
    expect(payment?.allocatedToPrincipalPaise).toBe(400_000);
    expect(payment?.allocatedToInterestPaise).toBe(interestThroughPaymentDay);

    const bill = await BillModel.findById(billId).lean();
    expect(bill?.outstandingPrincipalPaise).toBe(0);
    expect(bill?.amountPaidPaise).toBe(400_000);
    expect(bill?.totalAmountPaise).toBe(400_000);
    expect(bill?.interestAccruedPaise).toBe(interestThroughPaymentDay);

    const later = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: '2026-04-30T10:00:00.000+05:30' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(later.body.data.accruedInterestPaise).toBe(simpleInterestAfterSettlement);
    expect(later.body.data.accruedInterestPaise).not.toBe(
      calculateSimpleDailyInterestPaise(400_000 + interestThroughPaymentDay, 20, 2400),
    );
  });

  it('calculates interest at payment time even if the scheduled job has not run', async () => {
    const { ctx, billId } = await setupBill();
    expect(await InterestJobRunModel.countDocuments({ societyId: ctx.societyId })).toBe(0);

    const storedBefore = await BillModel.findById(billId).lean();
    expect(storedBefore?.interestAccruedPaise).toBe(0);

    const interest = calculateSimpleDailyInterestPaise(400_000, 15, 2400);
    const paid = await recordOffline(ctx.token, {
      billId,
      amountPaise: amountDuePaise(400_000, interest),
      paidAt: '2026-04-25T09:00:00.000+05:30',
      referenceNumber: `nojob-${billId}`,
      idempotencyKey: `nojob-${billId}`,
    });
    expect(paid.status).toBe(201);

    const payment = await PaymentModel.findById(paid.body.data.paymentId).lean();
    expect(payment?.allocatedToInterestPaise).toBe(interest);
    expect(payment?.allocatedToPrincipalPaise).toBe(400_000);
    expect(await InterestJobRunModel.countDocuments({ societyId: ctx.societyId })).toBe(0);
  });

  it('does not double-allocate or double-apply interest on a duplicate request', async () => {
    const { ctx, billId } = await setupBill();
    const interest = calculateSimpleDailyInterestPaise(400_000, 8, 2400);
    const payload = {
      billId,
      amountPaise: amountDuePaise(400_000, interest),
      paidAt: '2026-04-18T11:00:00.000+05:30',
      referenceNumber: `dup-${billId}`,
      idempotencyKey: `dup-${billId}`,
    };

    const first = await recordOffline(ctx.token, payload);
    const second = await recordOffline(ctx.token, payload);
    expect(first.status).toBe(201);
    expect(second.status).toBe(201);
    expect(second.body.data.paymentId).toBe(first.body.data.paymentId);
    expect(second.body.data.alreadySettled).toBe(true);

    expect(await PaymentModel.countDocuments({ billId, status: 'SUCCESS' })).toBe(1);
    const payment = await PaymentModel.findById(first.body.data.paymentId).lean();
    expect(payment?.allocatedToPrincipalPaise).toBe(400_000);
    expect(payment?.allocatedToInterestPaise).toBe(interest);

    const bill = await BillModel.findById(billId).lean();
    expect(bill?.outstandingPrincipalPaise).toBe(0);
    expect(bill?.amountPaidPaise).toBe(400_000);
    expect(bill?.interestAccruedPaise).toBe(interest);
  });

  it('leaves historical bills and payments unchanged', async () => {
    const historical = await setupBill();
    const histInterest = calculateSimpleDailyInterestPaise(400_000, 2, 2400);
    const histPay = await recordOffline(historical.ctx.token, {
      billId: historical.billId,
      amountPaise: amountDuePaise(400_000, histInterest),
      paidAt: '2026-04-12T10:00:00.000+05:30',
      referenceNumber: `hist-${historical.billId}`,
      idempotencyKey: `hist-${historical.billId}`,
    });
    expect(histPay.status).toBe(201);

    const histBillBefore = await BillModel.findById(historical.billId).lean();
    const histPaymentBefore = await PaymentModel.findById(histPay.body.data.paymentId).lean();

    const current = await setupBill();
    const currentInterest = calculateSimpleDailyInterestPaise(400_000, 12, 2400);
    const currentPay = await recordOffline(current.ctx.token, {
      billId: current.billId,
      amountPaise: amountDuePaise(400_000, currentInterest),
      paidAt: '2026-04-22T10:00:00.000+05:30',
      referenceNumber: `new-${current.billId}`,
      idempotencyKey: `new-${current.billId}`,
    });
    expect(currentPay.status).toBe(201);

    const histBillAfter = await BillModel.findById(historical.billId).lean();
    const histPaymentAfter = await PaymentModel.findById(histPay.body.data.paymentId).lean();
    expect(histBillAfter?.monthlyRatePaise).toBe(histBillBefore?.monthlyRatePaise);
    expect(histBillAfter?.totalAmountPaise).toBe(histBillBefore?.totalAmountPaise);
    expect(histBillAfter?.outstandingPrincipalPaise).toBe(histBillBefore?.outstandingPrincipalPaise);
    expect(histBillAfter?.interestAccruedPaise).toBe(histBillBefore?.interestAccruedPaise);
    expect(histBillAfter?.amountPaidPaise).toBe(histBillBefore?.amountPaidPaise);
    expect(histBillAfter?.status).toBe(histBillBefore?.status);
    expect(histBillAfter?.ownerNameSnapshot).toBe(histBillBefore?.ownerNameSnapshot);
    expect(histPaymentAfter?.amountPaise).toBe(histPaymentBefore?.amountPaise);
    expect(histPaymentAfter?.allocatedToPrincipalPaise).toBe(
      histPaymentBefore?.allocatedToPrincipalPaise,
    );
    expect(histPaymentAfter?.allocatedToInterestPaise).toBe(
      histPaymentBefore?.allocatedToInterestPaise,
    );
  });

  it('creates a resident payment order for principal plus current interest', async () => {
    const { ctx, owner, billId } = await setupBill();
    const { token: ownerToken } = await loginByEmail(app, owner.email);

    const opened = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}`)
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(opened.status).toBe(200);
    expect(opened.body.data.interestAccruedPaise).toBeGreaterThan(0);

    const order = await request(app)
      .post(`/api/v1/resident/billing/bills/${billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId);
    expect(order.status).toBe(201);
    expect(order.body.data.amountPaise).toBe(opened.body.data.totalPayablePaise);
    expect(order.body.data.amountPaise).toBe(
      opened.body.data.outstandingPrincipalPaise + opened.body.data.interestAccruedPaise,
    );
  });
});
