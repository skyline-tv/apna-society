import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginByEmail } from '../helpers/auth-login';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats, seedMonarchLikeSociety } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { WingModel } from '../../src/modules/society/models/wing.model';
import { BillModel } from '../../src/modules/billing/models/bill.model';
import { PaymentModel } from '../../src/modules/billing/models/payment.model';
import { ReceiptModel } from '../../src/modules/billing/models/receipt.model';
import { CollectionChargeModel } from '../../src/modules/collections/models/collection-charge.model';
import { CollectionPaymentModel } from '../../src/modules/collections/models/collection-payment.model';
import { CollectionReceiptModel } from '../../src/modules/collections/models/collection-receipt.model';
import { resetEnvCache, loadEnv } from '../../src/config/env';

const app = createApp();

async function login(email: string) {
  const { token } = await loginByEmail(app, email);
  return token;
}

const dueDate = '2026-12-31T00:00:00.000+05:30';

function basePayload(overrides: Record<string, unknown> = {}) {
  return {
    title: 'Diwali celebration collection',
    description: 'One-time festival contribution for lighting and snacks.',
    amountMode: 'PER_FLAT',
    assignmentType: 'ALL_FLATS',
    amountPaise: 10_000,
    dueDate,
    allowPartialPayment: false,
    ...overrides,
  };
}

describe('One-time collections', () => {
  it('previews and assigns all 140 configured flats including vacant ones', async () => {
    const ctx = await createAdminContext(app, 'col-140@example.com', 'COL140');
    await seedMonarchLikeSociety(ctx.societyId);

    const preview = await request(app)
      .post('/api/v1/admin/collections/preview')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send(basePayload());
    expect(preview.status).toBe(200);
    expect(preview.body.data.assignedFlatCount).toBe(140);
    expect(preview.body.data.expectedTotalPaise).toBe(1_400_000);

    const created = await request(app)
      .post('/api/v1/admin/collections')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send(basePayload());
    expect(created.status).toBe(201);
    expect(created.body.data.assignedFlatCount).toBe(140);
    expect(created.body.data.status).toBe('ACTIVE');

    const charges = await CollectionChargeModel.countDocuments({
      collectionId: created.body.data.id,
    });
    expect(charges).toBe(140);
    expect(await BillModel.countDocuments({ societyId: ctx.societyId })).toBe(0);
  }, 120_000);

  it('assigns one wing, selected flats, and custom amounts without duplicates', async () => {
    const ctx = await createAdminContext(app, 'col-mix@example.com', 'COLMIX');
    const { wing: wingA, flats: flatsA } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'A',
      flatRates: [4000, 4000, 5000, 5000],
    });
    const { flats: flatsB } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'B',
      flatRates: [4000, 4000],
    });

    const wingPreview = await request(app)
      .post('/api/v1/admin/collections/preview')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send(
        basePayload({
          title: 'Wing A decoration',
          assignmentType: 'WINGS',
          wingIds: [String(wingA._id)],
          amountPaise: 25_000,
        }),
      );
    expect(wingPreview.status).toBe(200);
    expect(wingPreview.body.data.assignedFlatCount).toBe(4);
    expect(wingPreview.body.data.expectedTotalPaise).toBe(100_000);

    const selected = await request(app)
      .post('/api/v1/admin/collections')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send(
        basePayload({
          title: 'Selected flats repair',
          assignmentType: 'SELECTED_FLATS',
          flatIds: [String(flatsA[0]._id), String(flatsB[0]._id)],
          amountPaise: 50_000,
        }),
      );
    expect(selected.status).toBe(201);
    expect(selected.body.data.assignedFlatCount).toBe(2);

    const custom = await request(app)
      .post('/api/v1/admin/collections')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send(
        basePayload({
          title: 'Custom amounts',
          amountMode: 'CUSTOM',
          assignmentType: 'SELECTED_FLATS',
          amountPaise: undefined,
          flatAmounts: [
            { flatId: String(flatsA[1]._id), amountPaise: 12_000 },
            { flatId: String(flatsA[2]._id), amountPaise: 18_000 },
          ],
        }),
      );
    expect(custom.status).toBe(201);
    expect(custom.body.data.expectedTotalPaise).toBe(30_000);

    const duplicate = await request(app)
      .post('/api/v1/admin/collections/preview')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send(
        basePayload({
          amountMode: 'CUSTOM',
          assignmentType: 'SELECTED_FLATS',
          amountPaise: undefined,
          flatAmounts: [
            { flatId: String(flatsA[1]._id), amountPaise: 12_000 },
            { flatId: String(flatsA[1]._id), amountPaise: 15_000 },
          ],
        }),
      );
    expect(duplicate.status).toBe(400);
    expect(duplicate.body.error.code).toBe('DUPLICATE_FLAT_ASSIGNMENT');

    const chargeCount = await CollectionChargeModel.countDocuments({
      collectionId: selected.body.data.id,
      flatId: flatsA[0]._id,
    });
    expect(chargeCount).toBe(1);
  });

  it('settles full payment, unique receipts, and ignores pending or failed attempts', async () => {
    const ctx = await createAdminContext(app, 'col-pay@example.com', 'COLPAY');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'P',
      flatRates: [4000, 4000],
    });
    const owner = await createUser({
      email: 'col-pay-owner@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });
    const otherOwner = await createUser({
      email: 'col-pay-other@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });
    const tenant = await createUser({
      email: 'col-pay-tenant@example.com',
      roles: ['TENANT'],
      societyId: ctx.societyId,
    });
    const guard = await createUser({
      email: 'col-pay-guard@example.com',
      roles: ['GUARD'],
      societyId: ctx.societyId,
    });
    await FlatModel.updateOne(
      { _id: flats[0]._id },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
    );
    await FlatModel.updateOne(
      { _id: flats[1]._id },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: otherOwner._id },
    );

    const created = await request(app)
      .post('/api/v1/admin/collections')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send(
        basePayload({
          title: 'Society event',
          assignmentType: 'SELECTED_FLATS',
          flatIds: [String(flats[0]._id), String(flats[1]._id)],
          amountPaise: 20_000,
          allowPartialPayment: true,
        }),
      );
    expect(created.status).toBe(201);
    const collectionId = created.body.data.id as string;

    const ownerToken = await login(owner.email!);
    const tenantToken = await login(tenant.email!);
    const guardToken = await login(guard.email!);
    const otherToken = await login(otherOwner.email!);

    const tenantDenied = await request(app)
      .get('/api/v1/resident/collections')
      .set('Authorization', `Bearer ${tenantToken}`)
      .set('x-society-id', ctx.societyId);
    expect(tenantDenied.status).toBe(403);

    const guardDenied = await request(app)
      .get('/api/v1/resident/collections')
      .set('Authorization', `Bearer ${guardToken}`)
      .set('x-society-id', ctx.societyId);
    expect(guardDenied.status).toBe(403);

    const listed = await request(app)
      .get('/api/v1/resident/collections')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId);
    expect(listed.status).toBe(200);
    expect(listed.body.data.items).toHaveLength(1);
    const chargeId = listed.body.data.items[0].id as string;
    expect(listed.body.data.items[0].outstandingPaise).toBe(20_000);

    const pendingOrder = await request(app)
      .post(`/api/v1/resident/collections/charges/${chargeId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId)
      .send({});
    expect(pendingOrder.status).toBe(201);

    const stillOpen = await CollectionChargeModel.findById(chargeId).lean();
    expect(stillOpen?.status).toBe('PENDING');
    expect(stillOpen?.amountPaidPaise).toBe(0);

    const failed = await request(app)
      .post('/api/v1/resident/collections/demo-complete')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId)
      .send({ orderId: pendingOrder.body.data.order.orderId, outcome: 'failure' });
    expect(failed.status).toBe(400);
    expect(await CollectionReceiptModel.countDocuments({ chargeId })).toBe(0);
    const afterFail = await CollectionChargeModel.findById(chargeId).lean();
    expect(afterFail?.status).toBe('PENDING');
    expect(afterFail?.amountPaidPaise).toBe(0);

    const partialOrder = await request(app)
      .post(`/api/v1/resident/collections/charges/${chargeId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId)
      .send({ amountPaise: 5_000 });
    expect(partialOrder.status).toBe(201);
    const partialPay = await request(app)
      .post('/api/v1/resident/collections/demo-complete')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId)
      .send({ orderId: partialOrder.body.data.order.orderId, outcome: 'success' });
    expect(partialPay.status).toBe(200);
    expect(partialPay.body.data.alreadySettled).toBe(false);
    expect(partialPay.body.data.receiptId).toBeTruthy();

    const afterPartial = await CollectionChargeModel.findById(chargeId).lean();
    expect(afterPartial?.status).toBe('PARTIALLY_PAID');
    expect(afterPartial?.amountPaidPaise).toBe(5_000);
    expect(afterPartial?.outstandingPaise).toBe(15_000);

    const fullOrder = await request(app)
      .post(`/api/v1/resident/collections/charges/${chargeId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId)
      .send({});
    const fullPay = await request(app)
      .post('/api/v1/resident/collections/demo-complete')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId)
      .send({ orderId: fullOrder.body.data.order.orderId, outcome: 'success' });
    expect(fullPay.status).toBe(200);

    const replay = await request(app)
      .post('/api/v1/resident/collections/demo-complete')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId)
      .send({ orderId: fullOrder.body.data.order.orderId, outcome: 'success' });
    expect(replay.status).toBe(200);
    expect(replay.body.data.alreadySettled).toBe(true);

    expect(await CollectionReceiptModel.countDocuments({ chargeId })).toBe(2);
    const paid = await CollectionChargeModel.findById(chargeId).lean();
    expect(paid?.status).toBe('PAID');
    expect(paid?.outstandingPaise).toBe(0);

    const receipt = await request(app)
      .get(`/api/v1/resident/collections/receipts/${fullPay.body.data.receiptId}`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId);
    expect(receipt.status).toBe(200);
    expect(receipt.body.data.pdfBase64).toBeTruthy();
    expect(receipt.body.data.receipt.collectionTitleSnapshot).toBe('Society event');

    const otherCharge = await CollectionChargeModel.findOne({
      collectionId,
      flatId: flats[1]._id,
    }).lean();
    const wrongOwner = await request(app)
      .post(`/api/v1/resident/collections/charges/${otherCharge!._id}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId)
      .send({});
    expect(wrongOwner.status).toBe(403);

    const otherList = await request(app)
      .get('/api/v1/resident/collections')
      .set('Authorization', `Bearer ${otherToken}`)
      .set('x-society-id', ctx.societyId);
    expect(otherList.body.data.items.every((row: { flatId: string }) => row.flatId === String(flats[1]._id))).toBe(
      true,
    );

    expect(await BillModel.countDocuments({ societyId: ctx.societyId })).toBe(0);
    expect(await PaymentModel.countDocuments({ societyId: ctx.societyId })).toBe(0);
    expect(await ReceiptModel.countDocuments({ societyId: ctx.societyId })).toBe(0);
  });

  it('rejects partial payment unless enabled, records reports, and preserves history on cancel', async () => {
    const ctx = await createAdminContext(app, 'col-hist@example.com', 'COLHST');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'H',
      flatRates: [4000, 4000],
    });
    const owner = await createUser({
      email: 'col-hist-owner@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });
    await FlatModel.updateOne(
      { _id: flats[0]._id },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
    );

    const created = await request(app)
      .post('/api/v1/admin/collections')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send(
        basePayload({
          title: 'Repair fund',
          assignmentType: 'SELECTED_FLATS',
          flatIds: [String(flats[0]._id), String(flats[1]._id)],
          amountPaise: 40_000,
          allowPartialPayment: false,
        }),
      );
    const collectionId = created.body.data.id as string;
    const ownerToken = await login(owner.email!);
    const ownerCharge = await CollectionChargeModel.findOne({
      collectionId,
      flatId: flats[0]._id,
    }).lean();

    const partialDenied = await request(app)
      .post(`/api/v1/resident/collections/charges/${ownerCharge!._id}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId)
      .send({ amountPaise: 10_000 });
    expect(partialDenied.status).toBe(400);
    expect(partialDenied.body.error.code).toBe('PARTIAL_PAYMENT_DISABLED');

    const order = await request(app)
      .post(`/api/v1/resident/collections/charges/${ownerCharge!._id}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId)
      .send({});
    await request(app)
      .post('/api/v1/resident/collections/demo-complete')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId)
      .send({ orderId: order.body.data.order.orderId, outcome: 'success' });

    process.env.OFFLINE_PAYMENTS_ENABLED = 'true';
    resetEnvCache();
    loadEnv();
    const vacantCharge = await CollectionChargeModel.findOne({
      collectionId,
      flatId: flats[1]._id,
    }).lean();
    const offline = await request(app)
      .post('/api/v1/admin/collections/payments/offline')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        chargeId: String(vacantCharge!._id),
        amountPaise: 40_000,
        paidAt: '2026-10-01T10:00:00.000Z',
        referenceNumber: 'CASH-1',
      });
    expect(offline.status).toBe(201);
    process.env.OFFLINE_PAYMENTS_ENABLED = 'false';
    resetEnvCache();
    loadEnv();

    const dashboard = await request(app)
      .get(`/api/v1/admin/collections/${collectionId}/dashboard`)
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(dashboard.status, JSON.stringify(dashboard.body)).toBe(200);
    expect(dashboard.body.data.assignedFlatCount).toBe(2);
    expect(dashboard.body.data.paidFlats).toBe(2);
    expect(dashboard.body.data.collectedPaise).toBe(80_000);

    const csv = await request(app)
      .get(`/api/v1/admin/collections/${collectionId}/charges.csv`)
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(csv.status).toBe(200);
    expect(csv.text).toContain('Assigned (INR)');
    expect(csv.text).toContain('H-101');

    const receiptCount = await CollectionReceiptModel.countDocuments({ collectionId });
    expect(receiptCount).toBe(2);

    const cancelled = await request(app)
      .post(`/api/v1/admin/collections/${collectionId}/cancel`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ reason: 'Event postponed by committee' });
    expect(cancelled.status).toBe(200);
    expect(cancelled.body.data.status).toBe('CANCELLED');

    expect(await CollectionReceiptModel.countDocuments({ collectionId })).toBe(2);
    expect(await CollectionPaymentModel.countDocuments({ collectionId, status: 'SUCCESS' })).toBe(2);
    const paidAfterCancel = await CollectionChargeModel.findById(ownerCharge!._id).lean();
    expect(paidAfterCancel?.status).toBe('PAID');
    expect(paidAfterCancel?.amountPaidPaise).toBe(40_000);

    expect(await BillModel.countDocuments({ societyId: ctx.societyId })).toBe(0);
    expect(await WingModel.countDocuments({ societyId: ctx.societyId })).toBe(1);
  });
});
