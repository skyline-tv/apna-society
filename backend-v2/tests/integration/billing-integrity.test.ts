import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { testOtpInbox } from '../helpers/setup';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { BillModel } from '../../src/modules/billing/models/bill.model';
import { PaymentModel } from '../../src/modules/billing/models/payment.model';
import { ReceiptModel } from '../../src/modules/billing/models/receipt.model';
import { PrincipalLedgerModel } from '../../src/modules/billing/models/principal-ledger.model';
import { calculateSimpleDailyInterestPaise } from '../../src/modules/billing/utils/money';
import { reconcileBillFinancials } from '../../src/modules/billing/services/financial-invariants.service';
import {
  signMockPayment,
  signMockWebhook,
} from '../../src/modules/billing/providers/mock-razorpay.provider';
import { resetEnvCache, loadEnv } from '../../src/config/env';

const app = createApp();

async function login(email: string) {
  await request(app).post('/api/v1/auth/request-otp').send({ email });
  const otp = testOtpInbox.find((item) => item.email === email)!.otp;
  const res = await request(app).post('/api/v1/auth/verify-otp').send({ email, otp });
  return res.body.data.accessToken as string;
}

async function setupBill(prefix: string) {
  const ctx = await createAdminContext(app, `${prefix}@example.com`, prefix.toUpperCase());
  const { flats } = await createWingWithFlats({
    societyId: ctx.societyId,
    code: 'Z',
    flatRates: [4000],
  });
  const owner = await createUser({
    email: `${prefix}-owner@example.com`,
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
  return {
    ctx,
    owner,
    billId: gen.body.data.created[0].id as string,
    flatId: String(flats[0]._id),
  };
}

describe('Partial-payment interest accuracy', () => {
  it('handles one partial, multiple partials, full settlement, and historical as-of', async () => {
    process.env.OFFLINE_PAYMENTS_ENABLED = 'true';
    resetEnvCache();
    loadEnv();

    const { ctx, billId } = await setupBill('led1');

    await request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        billId,
        amountPaise: 100_000,
        paidAt: '2026-04-15T10:00:00.000+05:30',
        referenceNumber: 'p1',
        idempotencyKey: 'led1-p1',
      });

    const mid = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: '2026-04-16T10:00:00.000+05:30' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(mid.body.data.accruedInterestPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 4, 2400) +
        calculateSimpleDailyInterestPaise(300_000, 2, 2400),
    );

    const historical = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: '2026-04-14T10:00:00.000+05:30' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(historical.body.data.principalOutstandingPaise).toBe(400_000);
    expect(historical.body.data.accruedInterestPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 4, 2400),
    );

    await request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        billId,
        amountPaise: 100_000,
        paidAt: '2026-04-18T10:00:00.000+05:30',
        referenceNumber: 'p2',
        idempotencyKey: 'led1-p2',
      });

    const multi = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: '2026-04-20T10:00:00.000+05:30' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(multi.body.data.principalOutstandingPaise).toBe(200_000);
    expect(multi.body.data.accruedInterestPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 4, 2400) +
        calculateSimpleDailyInterestPaise(300_000, 3, 2400) +
        calculateSimpleDailyInterestPaise(200_000, 3, 2400),
    );

    await request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        billId,
        amountPaise: 200_000,
        paidAt: '2026-04-21T10:00:00.000+05:30',
        referenceNumber: 'p3',
        idempotencyKey: 'led1-p3',
      });

    const settled = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: '2026-04-30T10:00:00.000+05:30' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(settled.body.data.principalOutstandingPaise).toBe(0);
    expect(settled.body.data.accruedInterestPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 4, 2400) +
        calculateSimpleDailyInterestPaise(300_000, 3, 2400) +
        calculateSimpleDailyInterestPaise(200_000, 3, 2400),
    );

    process.env.OFFLINE_PAYMENTS_ENABLED = 'false';
    resetEnvCache();
    loadEnv();
  });

  it('ignores failed payments and restores principal on refund for future interest', async () => {
    process.env.OFFLINE_PAYMENTS_ENABLED = 'true';
    resetEnvCache();
    loadEnv();

    const { ctx, owner, billId } = await setupBill('led2');
    const ownerToken = await login(owner.email);

    const order = await request(app)
      .post(`/api/v1/resident/billing/bills/${billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId);
    expect(order.status).toBe(201);

    const failed = await request(app)
      .post('/api/v1/resident/billing/verify-payment')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId)
      .send({
        orderId: order.body.data.order.orderId,
        paymentId: 'pay_fail',
        signature: 'bad',
      });
    expect(failed.status).toBe(403);

    const billAfterFail = await BillModel.findById(billId).lean();
    expect(billAfterFail?.outstandingPrincipalPaise).toBe(400_000);
    expect(await ReceiptModel.countDocuments({ billId })).toBe(0);

    const paid = await request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        billId,
        amountPaise: 400_000,
        paidAt: '2026-04-12T10:00:00.000+05:30',
        referenceNumber: 'ok',
        idempotencyKey: 'led2-ok',
      });
    expect(paid.status).toBe(201);

    const refund = await request(app)
      .post(`/api/v1/admin/payments/${paid.body.data.paymentId}/refund`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ reason: 'Chargeback' });
    expect(refund.status).toBe(200);

    const bill = await BillModel.findById(billId).lean();
    expect(bill?.outstandingPrincipalPaise).toBe(400_000);
    expect(bill?.amountPaidPaise).toBe(0);

    const ledger = await PrincipalLedgerModel.find({ billId }).sort({ effectiveAt: 1 }).lean();
    expect(ledger.map((e) => e.eventType)).toEqual([
      'OPENING',
      'PAYMENT_ALLOCATION',
      'REFUND_RESTORATION',
    ]);

    const beforeRefundAsOf = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: '2026-04-14T10:00:00.000+05:30' })
      .set('Authorization', `Bearer ${ctx.token}`);
    // Payment on 12th; refund is later (now). Historical as-of still sees principal at 0.
    expect(beforeRefundAsOf.body.data.principalOutstandingPaise).toBe(0);
    expect(beforeRefundAsOf.body.data.accruedInterestPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 1, 2400),
    );

    const afterRefundAsOf = await request(app)
      .get(`/api/v1/admin/billing/bills/${billId}/interest`)
      .query({ asOf: refund.body.data.refundedAt })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(afterRefundAsOf.body.data.principalOutstandingPaise).toBe(400_000);

    process.env.OFFLINE_PAYMENTS_ENABLED = 'false';
    resetEnvCache();
    loadEnv();
  });
});

describe('Concurrent bill generation', () => {
  it('does not create duplicate bills under concurrent HTTP generate requests', async () => {
    const ctx = await createAdminContext(app, 'cgen@example.com', 'CGEN1');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'C',
      flatRates: [4000],
    });
    const owner = await createUser({
      email: 'cgen-owner@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });
    await FlatModel.updateOne(
      { _id: flats[0]._id },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
    );

    const body = {
      billingPeriodStart: '2026-08-01T00:00:00.000+05:30',
      numberOfMonths: 1 as const,
    };
    const [a, b] = await Promise.all([
      request(app)
        .post('/api/v1/admin/billing/generate')
        .set('Authorization', `Bearer ${ctx.token}`)
        .send(body),
      request(app)
        .post('/api/v1/admin/billing/generate')
        .set('Authorization', `Bearer ${ctx.token}`)
        .send(body),
    ]);

    expect(a.status).toBe(201);
    expect(b.status).toBe(201);
    const createdTotal = a.body.data.createdCount + b.body.data.createdCount;
    expect(createdTotal).toBe(1);
    expect(a.body.data.conflictCount + b.body.data.conflictCount).toBeGreaterThanOrEqual(1);

    const bills = await BillModel.find({ societyId: ctx.societyId }).lean();
    expect(bills).toHaveLength(1);
    const numbers = new Set(bills.map((bill) => bill.billNumber));
    expect(numbers.size).toBe(1);
  });
});

describe('Concurrent payment settlement', () => {
  it('settles once when webhook and owner verify arrive together', async () => {
    const { ctx, owner, billId } = await setupBill('race1');
    const ownerToken = await login(owner.email);

    const order = await request(app)
      .post(`/api/v1/resident/billing/bills/${billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId);

    const gatewayPaymentId = `pay_race_${billId}`;
    const signature = signMockPayment(order.body.data.order.orderId, gatewayPaymentId);
    const payload = {
      id: `evt_race_${billId}`,
      event: 'payment.captured',
      payload: {
        payment: {
          entity: {
            id: gatewayPaymentId,
            order_id: order.body.data.order.orderId,
            status: 'captured',
            amount: 400_000,
          },
        },
      },
    };
    const raw = JSON.stringify(payload);
    const webhookSig = signMockWebhook(raw);

    const [verifyRes, webhookRes] = await Promise.all([
      request(app)
        .post('/api/v1/resident/billing/verify-payment')
        .set('Authorization', `Bearer ${ownerToken}`)
        .set('x-society-id', ctx.societyId)
        .send({
          orderId: order.body.data.order.orderId,
          paymentId: gatewayPaymentId,
          signature,
        }),
      request(app)
        .post('/api/v1/webhooks/payments')
        .set('x-razorpay-signature', webhookSig)
        .set('Content-Type', 'application/json')
        .send(payload),
    ]);

    expect([verifyRes.status, webhookRes.status].every((s) => s === 200)).toBe(true);
    expect(await PaymentModel.countDocuments({ billId, status: 'SUCCESS' })).toBe(1);
    expect(await ReceiptModel.countDocuments({ billId })).toBe(1);
    const bill = await BillModel.findById(billId).lean();
    expect(bill?.outstandingPrincipalPaise).toBe(0);
    expect(bill?.amountPaidPaise).toBe(400_000);
  });
});

describe('Financial invariants', () => {
  it('keeps balances, receipts, allocations and snapshots consistent', async () => {
    process.env.OFFLINE_PAYMENTS_ENABLED = 'true';
    resetEnvCache();
    loadEnv();

    const { ctx, billId } = await setupBill('inv1');
    const before = await BillModel.findById(billId).lean();
    const rate = before!.monthlyRatePaise;
    const ownerId = String(before!.ownerUserId);

    const pay = await request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        billId,
        amountPaise: 150_000,
        paidAt: '2026-04-12T10:00:00.000+05:30',
        referenceNumber: 'inv-p',
        idempotencyKey: 'inv1-p',
      });
    expect(pay.status).toBe(201);

    const reconciliation = await reconcileBillFinancials(ctx.societyId, billId);
    expect(reconciliation.ok).toBe(true);

    const bill = await BillModel.findById(billId).lean();
    expect(bill!.monthlyRatePaise).toBe(rate);
    expect(String(bill!.ownerUserId)).toBe(ownerId);
    expect(bill!.amountPaidPaise).toBe(150_000);
    expect(bill!.outstandingPrincipalPaise).toBe(250_000);
    expect(bill!.totalAmountPaise).toBe(bill!.baseAmountPaise + bill!.adjustmentsPaise);
    expect(bill!.amountPaidPaise + bill!.outstandingPrincipalPaise).toBe(bill!.totalAmountPaise);

    const refund = await request(app)
      .post(`/api/v1/admin/payments/${pay.body.data.paymentId}/refund`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ reason: 'Correction' });
    expect(refund.status).toBe(200);

    const payment = await PaymentModel.findById(pay.body.data.paymentId).lean();
    expect(payment?.status).toBe('REFUNDED');
    expect(payment?.allocatedToPrincipalPaise).toBe(150_000);
    expect(payment?.refundReason).toBe('Correction');

    await reconcileBillFinancials(ctx.societyId, billId);

    process.env.OFFLINE_PAYMENTS_ENABLED = 'false';
    resetEnvCache();
    loadEnv();
  });
});
