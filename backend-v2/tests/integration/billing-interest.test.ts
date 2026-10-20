import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { BillModel } from '../../src/modules/billing/models/bill.model';
import { calculateSimpleDailyInterestPaise } from '../../src/modules/billing/utils/money';
import { resetEnvCache, loadEnv } from '../../src/config/env';

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
});
