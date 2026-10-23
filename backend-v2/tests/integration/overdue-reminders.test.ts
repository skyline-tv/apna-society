import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { loginByEmail } from '../helpers/auth-login';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { BillModel } from '../../src/modules/billing/models/bill.model';
import { NotificationModel } from '../../src/modules/notifications/models/notification.model';
import { runOverdueReminderPass } from '../../src/modules/billing/services/overdue-reminder.service';
import { signMockPayment } from '../../src/modules/billing/providers/mock-razorpay.provider';

const app = createApp();

async function setupBill(prefix: string) {
  const ctx = await createAdminContext(app, `${prefix}-admin@example.com`, prefix.toUpperCase());
  const { flats } = await createWingWithFlats({
    societyId: ctx.societyId,
    code: 'O',
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
  expect(gen.status).toBe(201);
  const billId = gen.body.data.created[0].id as string;
  return { ctx, owner, billId, societyId: ctx.societyId };
}

describe('Overdue bill reminders', () => {
  it('notifies after successful generation and not on duplicate generation', async () => {
    const { owner, billId, societyId, ctx } = await setupBill('odue1');
    expect(
      await NotificationModel.countDocuments({
        type: 'BILL_GENERATED',
        relatedEntityId: billId,
        recipientUserId: owner._id,
      }),
    ).toBe(1);
    const note = await NotificationModel.findOne({
      type: 'BILL_GENERATED',
      relatedEntityId: billId,
    }).lean();
    expect(note?.title).toBe('Monthly Maintenance Bill Generated');
    expect(note?.metadata).toMatchObject({ billingMonth: 'April 2026' });

    const again = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-04-01T00:00:00.000+05:30', numberOfMonths: 1 });
    expect(again.status).toBe(201);
    expect(
      await NotificationModel.countDocuments({
        type: 'BILL_GENERATED',
        relatedEntityId: billId,
      }),
    ).toBe(1);
    void societyId;
  });

  it('sends one overdue reminder per civil day and stops after full payment', async () => {
    const { owner, billId, societyId } = await setupBill('odue2');
    const beforeDue = await runOverdueReminderPass(new Date('2026-04-10T12:00:00.000+05:30'));
    expect(
      await NotificationModel.countDocuments({
        type: 'BILL_OVERDUE',
        relatedEntityId: billId,
      }),
    ).toBe(0);
    void beforeDue;

    const first = await runOverdueReminderPass(new Date('2026-04-12T09:00:00.000+05:30'));
    expect(first.remindersCreated).toBeGreaterThanOrEqual(1);
    const overdue = await NotificationModel.find({
      type: 'BILL_OVERDUE',
      relatedEntityId: billId,
      recipientUserId: owner._id,
    }).lean();
    expect(overdue).toHaveLength(1);
    expect(overdue[0]?.title).toBe('Maintenance Bill Overdue');
    expect(overdue[0]?.metadata?.outstandingPrincipalPaise).toBeGreaterThan(0);

    const second = await runOverdueReminderPass(new Date('2026-04-12T18:00:00.000+05:30'));
    expect(second.remindersCreated).toBe(0);
    expect(
      await NotificationModel.countDocuments({
        type: 'BILL_OVERDUE',
        relatedEntityId: billId,
      }),
    ).toBe(1);

    const nextDay = await runOverdueReminderPass(new Date('2026-04-13T09:00:00.000+05:30'));
    expect(nextDay.remindersCreated).toBeGreaterThanOrEqual(1);

    const { token: ownerToken } = await loginByEmail(app, owner.email);
    const bill = await BillModel.findById(billId).lean();
    expect(bill).toBeTruthy();
    const order = await request(app)
      .post(`/api/v1/resident/billing/bills/${billId}/payment-order`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', societyId);
    expect(order.status).toBe(201);
    const paymentId = `pay_${billId}`;
    const verify = await request(app)
      .post('/api/v1/resident/billing/verify-payment')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', societyId)
      .send({
        orderId: order.body.data.order.orderId,
        paymentId,
        signature: signMockPayment(order.body.data.order.orderId, paymentId),
      });
    expect(verify.status).toBe(200);

    const afterPay = await runOverdueReminderPass(new Date('2026-04-14T09:00:00.000+05:30'));
    expect(afterPay.remindersCreated).toBe(0);
    expect(
      await NotificationModel.countDocuments({
        type: 'BILL_OVERDUE',
        relatedEntityId: billId,
      }),
    ).toBe(2);
  });
});
