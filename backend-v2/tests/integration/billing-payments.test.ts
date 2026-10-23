import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginByEmail } from '../helpers/auth-login';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { BillModel } from '../../src/modules/billing/models/bill.model';
import { PaymentModel } from '../../src/modules/billing/models/payment.model';
import { ReceiptModel } from '../../src/modules/billing/models/receipt.model';
import { AuditLogModel } from '../../src/modules/auth/models/audit-log.model';
import {
  signMockPayment,
  signMockWebhook,
} from '../../src/modules/billing/providers/mock-razorpay.provider';
import { settleSuccessfulPayment } from '../../src/modules/billing/services/payment.service';
import { resetEnvCache, loadEnv } from '../../src/config/env';

const app = createApp();

async function login(email: string) {
  const { token } = await loginByEmail(app, email);
  return token;
}

async function setupOccupiedBill(prefix: string) {
  const ctx = await createAdminContext(app, `${prefix}-admin@example.com`, prefix.toUpperCase());
  const { flats } = await createWingWithFlats({
    societyId: ctx.societyId,
    code: 'P',
    flatRates: [4000, 4000],
  });
  const owner = await createUser({
    email: `${prefix}-owner@example.com`,
    roles: ['OWNER'],
    societyId: ctx.societyId,
  });
  const otherOwner = await createUser({
    email: `${prefix}-other@example.com`,
    roles: ['OWNER'],
    societyId: ctx.societyId,
  });
  const tenant = await createUser({
    email: `${prefix}-tenant@example.com`,
    roles: ['TENANT'],
    societyId: ctx.societyId,
  });

  await FlatModel.updateOne(
    { _id: flats[0]._id },
    {
      occupancyStatus: 'TENANT_OCCUPIED',
      activeOwnerUserId: owner._id,
      activeTenantUserId: tenant._id,
    },
  );
  await FlatModel.updateOne(
    { _id: flats[1]._id },
    { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: otherOwner._id },
  );

  const gen = await request(app)
    .post('/api/v1/admin/billing/generate')
    .set('Authorization', `Bearer ${ctx.token}`)
    .send({ billingPeriodStart: '2026-07-01T00:00:00.000+05:30', numberOfMonths: 1 });

  const bill = gen.body.data.created.find(
    (b: { flatId: string }) => b.flatId === String(flats[0]._id),
  );
  const otherBill = gen.body.data.created.find(
    (b: { flatId: string }) => b.flatId === String(flats[1]._id),
  );

  return {
    ctx,
    owner,
    otherOwner,
    tenant,
    billId: bill.id as string,
    otherBillId: otherBill.id as string,
    flatId: String(flats[0]._id),
  };
}

describe('Billing payments', () => {
  it('allows owner to initiate payment and rejects tenant / wrong owner / amount manipulation', async () => {
    const setup = await setupOccupiedBill('pay1');
    const ownerToken = await login(`${setup.owner.email}`);
    const tenantToken = await login(`${setup.tenant.email}`);
    const otherToken = await login(`${setup.otherOwner.email}`);

    const tenantDenied = await request(app)
      .get('/api/v1/resident/billing/bills')
      .set('Authorization', `Bearer ${tenantToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(tenantDenied.status).toBe(403);

    const opened = await request(app)
      .get(`/api/v1/admin/billing/bills/${setup.billId}`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);
    expect(opened.status).toBe(200);
    const expectedDue =
      opened.body.data.outstandingPrincipalPaise + opened.body.data.interestAccruedPaise;

    const order = await request(app)
      .post(`/api/v1/resident/billing/bills/${setup.billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(order.status).toBe(201);
    expect(order.body.data.amountPaise).toBe(expectedDue);
    expect(order.body.data.order.orderId).toBeTruthy();

    const wrongOwner = await request(app)
      .post(`/api/v1/resident/billing/bills/${setup.billId}/payment-order`)
      .set('Authorization', `Bearer ${otherToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(wrongOwner.status).toBe(403);

    // Client cannot choose the amount — order is server-computed principal + current interest.
    expect(order.body.data.amountPaise).toBe(opened.body.data.totalPayablePaise);

    const badSig = await request(app)
      .post('/api/v1/resident/billing/verify-payment')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        orderId: order.body.data.order.orderId,
        paymentId: 'pay_bad',
        signature: 'not-valid',
      });
    expect(badSig.status).toBe(403);

    const receipts = await ReceiptModel.countDocuments({ societyId: setup.ctx.societyId });
    expect(receipts).toBe(0);
  });

  it('settles via valid verify once and creates exactly one receipt', async () => {
    const setup = await setupOccupiedBill('pay2');
    const ownerToken = await login(`${setup.owner.email}`);

    const order = await request(app)
      .post(`/api/v1/resident/billing/bills/${setup.billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);

    const gatewayPaymentId = `pay_${setup.billId}`;
    const signature = signMockPayment(order.body.data.order.orderId, gatewayPaymentId);

    const verify = await request(app)
      .post('/api/v1/resident/billing/verify-payment')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        orderId: order.body.data.order.orderId,
        paymentId: gatewayPaymentId,
        signature,
      });
    expect(verify.status).toBe(200);
    expect(verify.body.data.alreadySettled).toBe(false);
    expect(verify.body.data.receiptId).toBeTruthy();

    const again = await request(app)
      .post('/api/v1/resident/billing/verify-payment')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        orderId: order.body.data.order.orderId,
        paymentId: gatewayPaymentId,
        signature,
      });
    expect(again.status).toBe(200);
    expect(again.body.data.alreadySettled).toBe(true);

    const receiptCount = await ReceiptModel.countDocuments({
      societyId: setup.ctx.societyId,
      billId: setup.billId,
    });
    expect(receiptCount).toBe(1);

    const bill = await BillModel.findById(setup.billId).lean();
    expect(bill?.status).toBe('PAID');
    expect(bill?.outstandingPrincipalPaise).toBe(0);

    const receipt = await request(app)
      .get(`/api/v1/resident/billing/receipts/${verify.body.data.receiptId}`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(receipt.status).toBe(200);
    expect(receipt.body.data.pdfBase64).toBeTruthy();
  });

  it('settles via webhook idempotently and rejects invalid webhook signature', async () => {
    const setup = await setupOccupiedBill('pay3');
    const ownerToken = await login(`${setup.owner.email}`);

    const order = await request(app)
      .post(`/api/v1/resident/billing/bills/${setup.billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);

    const gatewayPaymentId = `pay_wh_${setup.billId}`;
    const payload = {
      id: `evt_${setup.billId}`,
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

    const bad = await request(app)
      .post('/api/v1/webhooks/payments')
      .set('x-razorpay-signature', 'invalid')
      .set('Content-Type', 'application/json')
      .send(payload);
    expect(bad.status).toBe(403);

    const sig = signMockWebhook(raw);
    const first = await request(app)
      .post('/api/v1/webhooks/payments')
      .set('x-razorpay-signature', sig)
      .set('Content-Type', 'application/json')
      .send(payload);
    expect(first.status).toBe(200);
    expect(first.body.data.settled).toBe(true);

    const second = await request(app)
      .post('/api/v1/webhooks/payments')
      .set('x-razorpay-signature', sig)
      .set('Content-Type', 'application/json')
      .send(payload);
    expect(second.status).toBe(200);
    expect(second.body.data.alreadySettled).toBe(true);

    expect(await ReceiptModel.countDocuments({ billId: setup.billId })).toBe(1);
  });

  it('requires offline payments configuration and preserves refund audit history', async () => {
    process.env.OFFLINE_PAYMENTS_ENABLED = 'false';
    resetEnvCache();
    loadEnv();

    const setup = await setupOccupiedBill('pay4');
    const denied = await request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        billId: setup.billId,
        amountPaise: 400_000,
        paidAt: '2026-07-05T10:00:00.000Z',
        referenceNumber: 'OFF-1',
      });
    expect(denied.status).toBe(403);

    process.env.OFFLINE_PAYMENTS_ENABLED = 'true';
    resetEnvCache();
    loadEnv();

    const recorded = await request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        billId: setup.billId,
        amountPaise: 400_000,
        paidAt: '2026-07-05T10:00:00.000Z',
        referenceNumber: 'OFF-OK',
        notes: 'Cash',
        idempotencyKey: 'offline-ok-1',
      });
    expect(recorded.status).toBe(201);

    const paymentId = recorded.body.data.paymentId as string;
    const refund = await request(app)
      .post(`/api/v1/admin/payments/${paymentId}/refund`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ reason: 'Duplicate entry' });
    expect(refund.status).toBe(200);
    expect(refund.body.data.status).toBe('REFUNDED');

    const payment = await PaymentModel.findById(paymentId).lean();
    expect(payment?.status).toBe('REFUNDED');
    expect(payment?.refundReason).toBe('Duplicate entry');

    const bill = await BillModel.findById(setup.billId).lean();
    expect(bill?.outstandingPrincipalPaise).toBe(400_000);

    const audit = await AuditLogModel.countDocuments({
      societyId: setup.ctx.societyId,
      action: 'PAYMENT_REFUNDED',
    });
    expect(audit).toBe(1);

    process.env.OFFLINE_PAYMENTS_ENABLED = 'false';
    resetEnvCache();
    loadEnv();
  });

  it('rejects cross-society bill/payment access and rolls back failed settlement', async () => {
    const setup = await setupOccupiedBill('pay5');
    const other = await createAdminContext(app, 'pay5-other-admin@example.com', 'PAY5B');

    const cross = await request(app)
      .get(`/api/v1/admin/billing/bills/${setup.billId}`)
      .set('Authorization', `Bearer ${other.token}`);
    expect(cross.status).toBe(404);

    const ownerToken = await login(`${setup.owner.email}`);
    const order = await request(app)
      .post(`/api/v1/resident/billing/bills/${setup.billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);

    process.env.TEST_FORCED_TRANSACTION_FAILURE = 'payment_settle';
    const payment = await PaymentModel.findById(order.body.data.paymentId);
    await expect(
      settleSuccessfulPayment({
        societyId: setup.ctx.societyId,
        payment: payment!,
        gatewayPaymentId: `force_${setup.billId}`,
        signatureVerified: true,
        paidAt: new Date(),
        source: 'verify',
      }),
    ).rejects.toThrow(/TEST_FORCED_TRANSACTION_FAILURE/);

    delete process.env.TEST_FORCED_TRANSACTION_FAILURE;

    const reloaded = await PaymentModel.findById(order.body.data.paymentId).lean();
    expect(reloaded?.status).toBe('PENDING');
    expect(await ReceiptModel.countDocuments({ paymentId: order.body.data.paymentId })).toBe(0);
    const bill = await BillModel.findById(setup.billId).lean();
    expect(bill?.outstandingPrincipalPaise).toBe(400_000);
  });

  it('prevents concurrent double settlement via webhook races', async () => {
    const setup = await setupOccupiedBill('pay6');
    const ownerToken = await login(`${setup.owner.email}`);
    const order = await request(app)
      .post(`/api/v1/resident/billing/bills/${setup.billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);

    const gatewayPaymentId = `pay_race_${setup.billId}`;
    const payload = {
      id: `evt_race_${setup.billId}`,
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
    const sig = signMockWebhook(raw);

    const [a, b] = await Promise.all([
      request(app)
        .post('/api/v1/webhooks/payments')
        .set('x-razorpay-signature', sig)
        .set('Content-Type', 'application/json')
        .send(payload),
      request(app)
        .post('/api/v1/webhooks/payments')
        .set('x-razorpay-signature', sig)
        .set('Content-Type', 'application/json')
        .send(payload),
    ]);

    expect([a.status, b.status].every((s) => s === 200)).toBe(true);
    expect(await ReceiptModel.countDocuments({ billId: setup.billId })).toBe(1);
    expect(await PaymentModel.countDocuments({ billId: setup.billId, status: 'SUCCESS' })).toBe(1);
    const bill = await BillModel.findById(setup.billId).lean();
    expect(bill?.outstandingPrincipalPaise).toBe(0);
  });

  it('settles mock checkout via demo-complete without a client signature', async () => {
    const setup = await setupOccupiedBill('paydemo');
    const ownerToken = await login(`${setup.owner.email}`);

    const failedOrder = await request(app)
      .post(`/api/v1/resident/billing/bills/${setup.billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(failedOrder.status).toBe(201);
    expect(failedOrder.body.data.order.provider).toBe('razorpay-mock');

    const failed = await request(app)
      .post('/api/v1/resident/billing/demo-complete')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        orderId: failedOrder.body.data.order.orderId,
        outcome: 'failure',
      });
    expect(failed.status).toBe(400);
    expect(failed.body.error.code).toBe('DEMO_PAYMENT_FAILED');

    const order = await request(app)
      .post(`/api/v1/resident/billing/bills/${setup.billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(order.status).toBe(201);

    const success = await request(app)
      .post('/api/v1/resident/billing/demo-complete')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        orderId: order.body.data.order.orderId,
        outcome: 'success',
      });
    expect(success.status).toBe(200);
    expect(success.body.data.alreadySettled).toBe(false);
    expect(success.body.data.receiptId).toBeTruthy();

    const again = await request(app)
      .post('/api/v1/resident/billing/demo-complete')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        orderId: order.body.data.order.orderId,
        outcome: 'success',
      });
    expect(again.status).toBe(200);
    expect(again.body.data.alreadySettled).toBe(true);

    const bill = await BillModel.findById(setup.billId).lean();
    expect(bill?.status).toBe('PAID');
    expect(bill?.outstandingPrincipalPaise).toBe(0);
    expect(await ReceiptModel.countDocuments({ billId: setup.billId })).toBe(1);
  });

  it('shows zero outstanding after a confirmed payment and keeps failed/pending from settling', async () => {
    const setup = await setupOccupiedBill('paysettle');
    const ownerToken = await login(`${setup.owner.email}`);

    const opened = await request(app)
      .get(`/api/v1/resident/billing/bills/${setup.billId}`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(opened.status).toBe(200);
    const originalPayable = opened.body.data.totalPayablePaise as number;
    expect(originalPayable).toBeGreaterThan(0);

    const failedOrder = await request(app)
      .post(`/api/v1/resident/billing/bills/${setup.billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    const failed = await request(app)
      .post('/api/v1/resident/billing/demo-complete')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({ orderId: failedOrder.body.data.order.orderId, outcome: 'failure' });
    expect(failed.status).toBe(400);

    const afterFail = await request(app)
      .get(`/api/v1/resident/billing/bills/${setup.billId}`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(afterFail.body.data.totalPayablePaise).toBe(originalPayable);
    expect(afterFail.body.data.status).not.toBe('PAID');

    const failedReceipt = await request(app)
      .get(`/api/v1/resident/billing/payments/${failedOrder.body.data.paymentId}/receipt`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(failedReceipt.status).toBe(400);
    expect(failedReceipt.body.error.code).toBe('RECEIPT_NOT_AVAILABLE');

    const pendingOrder = await request(app)
      .post(`/api/v1/resident/billing/bills/${setup.billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    const pendingReceipt = await request(app)
      .get(`/api/v1/resident/billing/payments/${pendingOrder.body.data.paymentId}/receipt`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(pendingReceipt.status).toBe(400);

    const success = await request(app)
      .post('/api/v1/resident/billing/demo-complete')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({ orderId: pendingOrder.body.data.order.orderId, outcome: 'success' });
    expect(success.status).toBe(200);
    expect(success.body.data.receiptId).toBeTruthy();

    const paid = await request(app)
      .get(`/api/v1/resident/billing/bills/${setup.billId}`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(paid.status).toBe(200);
    expect(paid.body.data.status).toBe('PAID');
    expect(paid.body.data.outstandingPrincipalPaise).toBe(0);
    expect(paid.body.data.totalPayablePaise).toBe(0);
    expect(paid.body.data.interestOutstandingPaise).toBe(0);

    const duplicate = await request(app)
      .post('/api/v1/resident/billing/demo-complete')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({ orderId: pendingOrder.body.data.order.orderId, outcome: 'success' });
    expect(duplicate.body.data.alreadySettled).toBe(true);
    expect(duplicate.body.data.receiptId).toBe(success.body.data.receiptId);
    expect(await ReceiptModel.countDocuments({ billId: setup.billId })).toBe(1);

    const receipt = await request(app)
      .get(`/api/v1/resident/billing/payments/${pendingOrder.body.data.paymentId}/receipt`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(receipt.status).toBe(200);
    const pdf = Buffer.from(receipt.body.data.pdfBase64, 'base64').toString('utf8');
    expect(pdf.startsWith('%PDF-1.4')).toBe(true);
    expect(pdf).toContain('SUCCESSFUL');
    expect(pdf).toContain('APNA SOCIETY');
    expect(pdf).toContain(receipt.body.data.receipt.receiptNumber);

    const otherToken = await login(`${setup.otherOwner.email}`);
    const cross = await request(app)
      .get(`/api/v1/resident/billing/payments/${pendingOrder.body.data.paymentId}/receipt`)
      .set('Authorization', `Bearer ${otherToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(cross.status).toBe(403);
  });

  it('settles partial and multiple confirmed payments without double-counting', async () => {
    process.env.OFFLINE_PAYMENTS_ENABLED = 'true';
    resetEnvCache();
    loadEnv();

    const setup = await setupOccupiedBill('paypartial');
    const first = await request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        billId: setup.billId,
        amountPaise: 150_000,
        paidAt: '2026-07-20T10:00:00.000Z',
        referenceNumber: 'PART-1',
        idempotencyKey: 'partial-1',
      });
    expect(first.status).toBe(201);

    const afterFirst = await request(app)
      .get(`/api/v1/admin/billing/bills/${setup.billId}`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);
    expect(afterFirst.body.data.outstandingPrincipalPaise).toBe(250_000);
    expect(afterFirst.body.data.totalPayablePaise).toBeGreaterThanOrEqual(250_000);
    expect(afterFirst.body.data.status).not.toBe('PAID');

    const second = await request(app)
      .post('/api/v1/admin/payments/offline')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        billId: setup.billId,
        amountPaise: afterFirst.body.data.totalPayablePaise,
        paidAt: '2026-07-21T10:00:00.000Z',
        referenceNumber: 'PART-2',
        idempotencyKey: 'partial-2',
      });
    expect(second.status).toBe(201);

    const settled = await request(app)
      .get(`/api/v1/admin/billing/bills/${setup.billId}`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);
    expect(settled.body.data.status).toBe('PAID');
    expect(settled.body.data.outstandingPrincipalPaise).toBe(0);
    expect(settled.body.data.totalPayablePaise).toBe(0);
    expect(await ReceiptModel.countDocuments({ billId: setup.billId })).toBe(2);

    process.env.OFFLINE_PAYMENTS_ENABLED = 'false';
    resetEnvCache();
    loadEnv();
  });

  it('reuses a historical receipt instead of creating a duplicate', async () => {
    const setup = await setupOccupiedBill('payhist');
    const ownerToken = await login(`${setup.owner.email}`);
    const order = await request(app)
      .post(`/api/v1/resident/billing/bills/${setup.billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    const success = await request(app)
      .post('/api/v1/resident/billing/demo-complete')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({ orderId: order.body.data.order.orderId, outcome: 'success' });
    expect(success.status).toBe(200);

    const paymentId = order.body.data.paymentId as string;
    await ReceiptModel.deleteOne({ paymentId });
    expect(await ReceiptModel.countDocuments({ paymentId })).toBe(0);

    const first = await request(app)
      .get(`/api/v1/resident/billing/payments/${paymentId}/receipt`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(first.status).toBe(200);
    const second = await request(app)
      .get(`/api/v1/resident/billing/payments/${paymentId}/receipt`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(second.status).toBe(200);
    expect(second.body.data.receipt.id).toBe(first.body.data.receipt.id);
    expect(await ReceiptModel.countDocuments({ paymentId })).toBe(1);
  });
});
