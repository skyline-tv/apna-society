import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { BillModel } from '../../src/modules/billing/models/bill.model';
import { FlatAdditionalServiceModel } from '../../src/modules/billing/models/additional-service.model';
import {
  ADDITIONAL_SERVICE_LIMIT_CODE,
  ADDITIONAL_SERVICE_LIMIT_MESSAGE,
  MAX_ACTIVE_ADDITIONAL_SERVICES_PER_FLAT,
} from '../../src/modules/billing/utils/additional-service-limit';
import { loginByEmail } from '../helpers/auth-login';

const app = createApp();

describe('Additional services and attached unassigned bills', () => {
  it('includes active services on future bills, snapshots them, and ignores later edits', async () => {
    const ctx = await createAdminContext(app, 'svc-admin@example.com', 'SVC_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'A',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);

    const parking = await request(app)
      .post('/api/v1/admin/billing/additional-services')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        flatId,
        name: 'Additional car parking',
        monthlyChargePaise: 50_000,
        quantity: 1,
        effectiveFrom: '2026-04-01T00:00:00.000+05:30',
      });
    expect(parking.status).toBe(201);

    const twoWheeler = await request(app)
      .post('/api/v1/admin/billing/additional-services')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        flatId,
        name: 'Additional two-wheeler parking',
        monthlyChargePaise: 20_000,
        quantity: 1,
        effectiveFrom: '2026-04-01T00:00:00.000+05:30',
      });
    expect(twoWheeler.status).toBe(201);

    const april = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-04-01T00:00:00.000+05:30', numberOfMonths: 1 });
    expect(april.status).toBe(201);
    expect(april.body.data.createdCount).toBe(1);
    const aprilBill = april.body.data.created[0];
    expect(aprilBill.baseAmountPaise).toBe(400_000);
    expect(aprilBill.additionalServicesTotalPaise).toBe(70_000);
    expect(aprilBill.totalAmountPaise).toBe(470_000);
    expect(aprilBill.lineItems).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ type: 'MAINTENANCE', amountPaise: 400_000 }),
        expect.objectContaining({
          type: 'ADDITIONAL_SERVICE',
          name: 'Additional car parking',
          amountPaise: 50_000,
        }),
        expect.objectContaining({
          type: 'ADDITIONAL_SERVICE',
          name: 'Additional two-wheeler parking',
          amountPaise: 20_000,
        }),
      ]),
    );

    await request(app)
      .patch(`/api/v1/admin/billing/additional-services/${parking.body.data.id}`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ monthlyChargePaise: 80_000 });

    await request(app)
      .post(`/api/v1/admin/billing/additional-services/${twoWheeler.body.data.id}/deactivate`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ reason: 'Slot surrendered' });

    const storedApril = await BillModel.findById(aprilBill.id).lean();
    expect(storedApril?.totalAmountPaise).toBe(470_000);
    expect(storedApril?.additionalServicesTotalPaise).toBe(70_000);

    const may = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-05-01T00:00:00.000+05:30', numberOfMonths: 1 });
    expect(may.status).toBe(201);
    const mayBill = may.body.data.created[0];
    expect(mayBill.additionalServicesTotalPaise).toBe(80_000);
    expect(mayBill.totalAmountPaise).toBe(480_000);
    expect(
      mayBill.lineItems.some(
        (item: { name: string }) => item.name === 'Additional two-wheeler parking',
      ),
    ).toBe(false);
  });

  it('attaches unassigned bills to a newly assigned owner without duplicating amounts', async () => {
    const ctx = await createAdminContext(app, 'attach-admin@example.com', 'ATTACH_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'B',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);

    const generated = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-06-01T00:00:00.000+05:30', numberOfMonths: 1 });
    expect(generated.status).toBe(201);
    const billId = generated.body.data.created[0].id;
    expect(generated.body.data.created[0].ownerUserId).toBeUndefined();

    const owner = await createUser({
      email: 'new-owner@example.com',
      name: 'New Owner',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });

    const assigned = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: String(owner._id), effectiveFrom: '2026-06-15' });
    expect(assigned.status).toBe(201);

    const bill = await BillModel.findById(billId).lean();
    expect(String(bill!.ownerUserId)).toBe(String(owner._id));
    expect(bill!.totalAmountPaise).toBe(400_000);
    expect(bill!.outstandingPrincipalPaise).toBe(400_000);

    const ownerLogin = await loginByEmail(app, 'new-owner@example.com');
    const ownerBills = await request(app)
      .get('/api/v1/resident/billing/bills')
      .set('Authorization', `Bearer ${ownerLogin.token}`);
    expect(ownerBills.status).toBe(200);
    expect(ownerBills.body.data.items).toHaveLength(1);
    expect(ownerBills.body.data.items[0].id).toBe(billId);

    const otherOwner = await createUser({
      email: 'other-owner@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });
    const otherLogin = await loginByEmail(app, otherOwner.email);
    const otherBills = await request(app)
      .get('/api/v1/resident/billing/bills')
      .set('Authorization', `Bearer ${otherLogin.token}`);
    expect(otherBills.status).toBe(200);
    expect(otherBills.body.data.items).toHaveLength(0);

    const otherDetail = await request(app)
      .get(`/api/v1/resident/billing/bills/${billId}`)
      .set('Authorization', `Bearer ${otherLogin.token}`);
    expect(otherDetail.status).toBe(403);
  });

  it('does not duplicate additional service charges on repeated generation', async () => {
    const ctx = await createAdminContext(app, 'dup-svc@example.com', 'DUP_SVC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'C',
      flatRates: [4000],
    });
    await FlatAdditionalServiceModel.create({
      societyId: ctx.societyId,
      flatId: flats[0]._id,
      name: 'Additional car parking',
      monthlyChargePaise: 50_000,
      quantity: 1,
      effectiveFrom: new Date('2026-07-01T00:00:00.000+05:30'),
      isActive: true,
      createdBy: ctx.userId,
    });

    const first = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-07-01T00:00:00.000+05:30', numberOfMonths: 1 });
    const second = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ billingPeriodStart: '2026-07-01T00:00:00.000+05:30', numberOfMonths: 1 });

    expect(first.body.data.createdCount).toBe(1);
    expect(first.body.data.created[0].totalAmountPaise).toBe(450_000);
    expect(second.body.data.createdCount).toBe(0);
    expect(second.body.data.conflictCount).toBe(1);
    expect(await BillModel.countDocuments({ societyId: ctx.societyId })).toBe(1);
  });

  it('allows 10 active services per flat, rejects the 11th, and frees a slot on deactivate', async () => {
    const ctx = await createAdminContext(app, 'cap-admin@example.com', 'CAP_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'D',
      flatRates: [4000, 5000],
    });
    const flatId = String(flats[0]._id);
    const otherFlatId = String(flats[1]._id);
    await FlatAdditionalServiceModel.createIndexes();

    const created = [];
    for (let i = 1; i <= MAX_ACTIVE_ADDITIONAL_SERVICES_PER_FLAT; i += 1) {
      const res = await addService(ctx.token, flatId, `Service ${i}`, 10_000 * i);
      expect(res.status).toBe(201);
      created.push(res.body.data);
    }
    expect(created).toHaveLength(10);

    const listed = await request(app)
      .get('/api/v1/admin/billing/additional-services')
      .query({ flatId, isActive: 'true' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(listed.status).toBe(200);
    expect(listed.body.data.activeCount).toBe(10);
    expect(listed.body.data.maxActive).toBe(10);
    expect(listed.body.data.pagination.total).toBe(10);

    const eleventh = await addService(ctx.token, flatId, 'Service 11', 5_000);
    expect(eleventh.status).toBe(409);
    expect(eleventh.body.error.code).toBe(ADDITIONAL_SERVICE_LIMIT_CODE);
    expect(eleventh.body.error.message).toBe(ADDITIONAL_SERVICE_LIMIT_MESSAGE);

    const otherFlat = await addService(ctx.token, otherFlatId, 'Other flat parking', 20_000);
    expect(otherFlat.status).toBe(201);

    const deactivated = await request(app)
      .post(`/api/v1/admin/billing/additional-services/${created[0].id}/deactivate`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ reason: 'Slot surrendered' });
    expect(deactivated.status).toBe(200);
    expect(deactivated.body.data.isActive).toBe(false);

    const replacement = await addService(ctx.token, flatId, 'Replacement storage', 30_000);
    expect(replacement.status).toBe(201);

    const stillCapped = await addService(ctx.token, flatId, 'Should fail', 1_000);
    expect(stillCapped.status).toBe(409);

    const parkedInactive = await request(app)
      .post('/api/v1/admin/billing/additional-services')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        flatId,
        name: 'Parked inactive',
        monthlyChargePaise: 1_000,
        quantity: 1,
        effectiveFrom: '2026-04-01T00:00:00.000+05:30',
        isActive: false,
      });
    expect(parkedInactive.status).toBe(201);

    const reactivate = await request(app)
      .patch(`/api/v1/admin/billing/additional-services/${parkedInactive.body.data.id}`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ isActive: true });
    expect(reactivate.status).toBe(409);
    expect(reactivate.body.error.code).toBe(ADDITIONAL_SERVICE_LIMIT_CODE);

    const active = await FlatAdditionalServiceModel.countDocuments({
      societyId: ctx.societyId,
      flatId: flats[0]._id,
      isActive: true,
    });
    expect(active).toBe(10);
  });

  it('never lets concurrent creates exceed 10 active services on a flat', async () => {
    const ctx = await createAdminContext(app, 'race-admin@example.com', 'RACE_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'E',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);
    await FlatAdditionalServiceModel.createIndexes();

    const attempts = Array.from({ length: 12 }, (_, i) =>
      addService(ctx.token, flatId, `Concurrent ${i + 1}`, 15_000),
    );
    const results = await Promise.all(attempts);
    const created = results.filter((res) => res.status === 201);
    const rejected = results.filter((res) => res.status === 409);

    expect(created).toHaveLength(10);
    expect(rejected).toHaveLength(2);
    expect(rejected.every((res) => res.body.error.code === ADDITIONAL_SERVICE_LIMIT_CODE)).toBe(
      true,
    );

    const active = await FlatAdditionalServiceModel.countDocuments({
      societyId: ctx.societyId,
      flatId: flats[0]._id,
      isActive: true,
    });
    expect(active).toBe(10);
  });
});

async function addService(
  token: string,
  flatId: string,
  name: string,
  monthlyChargePaise: number,
) {
  return request(app)
    .post('/api/v1/admin/billing/additional-services')
    .set('Authorization', `Bearer ${token}`)
    .send({
      flatId,
      name,
      monthlyChargePaise,
      quantity: 1,
      effectiveFrom: '2026-04-01T00:00:00.000+05:30',
    });
}
