import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginByEmail } from '../helpers/auth-login';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { OccupancyRecordModel } from '../../src/modules/society/models/occupancy-record.model';
import { UserModel } from '../../src/modules/users/models/user.model';
import { VehicleModel } from '../../src/modules/vehicles/models/vehicle.model';

const app = createApp();

async function login(email: string) {
  const { token } = await loginByEmail(app, email);
  return token;
}

describe('Admin resident vehicle registration', () => {
  it('registers a resident with no vehicles, one vehicle, or many, and links them', async () => {
    const ctx = await createAdminContext(app, 'veh-reg-admin@example.com', 'VEH_REG');
    const { flats, wing } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'V',
      flatRates: [4000, 4000],
    });
    const vacantId = String(flats[0]._id);
    const otherFlatId = String(flats[1]._id);

    const none = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'No Car Owner',
        email: 'nocar@example.com',
        role: 'OWNER',
        username: 'nocarowner',
        flatId: vacantId,
      });
    expect(none.status).toBe(201);
    expect(none.body.data.flatAssigned).toBe(true);
    expect(none.body.data.vehicles).toBeUndefined();
    expect(
      await VehicleModel.countDocuments({ registeredUserId: none.body.data.user.id }),
    ).toBe(0);

    await request(app)
      .post(`/api/v1/admin/flats/${vacantId}/end-owner-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'Freeing flat for next owner' });

    const one = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'One Car Owner',
        email: 'onecar@example.com',
        role: 'OWNER',
        username: 'onecarowner',
        flatId: vacantId,
        vehicles: [
          {
            vehicleType: 'FOUR_WHEELER',
            registrationNumber: 'MH12AB1001',
            make: 'Honda',
            model: 'City',
          },
        ],
      });
    expect(one.status).toBe(201);
    expect(one.body.data.flatAssigned).toBe(true);
    expect(one.body.data.vehicles).toHaveLength(1);
    expect(one.body.data.vehicles[0].registeredUserId).toBe(one.body.data.user.id);
    expect(one.body.data.vehicles[0].flatId).toBe(vacantId);
    expect(one.body.data.vehicles[0].societyId).toBe(ctx.societyId);
    expect(one.body.data.vehicles[0].registrationNumber).toBe('MH12AB1001');

    await request(app)
      .post(`/api/v1/admin/flats/${vacantId}/end-owner-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'Freeing flat for multi owner' });

    const many = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'Two Car Owner',
        email: 'twocar@example.com',
        role: 'OWNER',
        username: 'twocarowner',
        flatId: vacantId,
        vehicles: [
          {
            vehicleType: 'TWO_WHEELER',
            registrationNumber: 'MH 12 AB 2001',
            make: 'Honda',
            model: 'Activa',
          },
          {
            vehicleType: 'FOUR_WHEELER',
            registrationNumber: 'mh12-ab-2002',
            make: 'Hyundai',
            model: 'Creta',
          },
        ],
      });
    expect(many.status).toBe(201);
    expect(many.body.data.vehicles).toHaveLength(2);

    const listed = await request(app)
      .get('/api/v1/admin/vehicles')
      .query({ registeredUserId: many.body.data.user.id, isActive: 'true' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(listed.status).toBe(200);
    expect(listed.body.data.items).toHaveLength(2);
    for (const item of listed.body.data.items) {
      expect(item.residentName).toBe('Two Car Owner');
      expect(item.flatNumber).toBe(flats[0].number);
      expect(item.wingCode).toBe(wing.code);
      expect(item.societyId).toBe(ctx.societyId);
      expect(item.societyName).toBeTruthy();
      expect(item.registeredUserId).toBe(many.body.data.user.id);
      expect(item.flatId).toBe(vacantId);
    }

    const occupancies = await OccupancyRecordModel.countDocuments({
      userId: many.body.data.user.id,
      flatId: vacantId,
      status: 'ACTIVE',
    });
    expect(occupancies).toBe(1);

    const otherOwner = await createUser({
      email: 'other-veh-owner@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });
    const hijack = await request(app)
      .post('/api/v1/admin/vehicles')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        flatId: vacantId,
        registeredUserId: String(otherOwner._id),
        vehicleType: 'FOUR_WHEELER',
        registrationNumber: 'MH12AB3001',
      });
    expect(hijack.status).toBe(403);
    expect(hijack.body.error.code).toBe('NOT_FLAT_OCCUPANT');

    const wrongFlat = await request(app)
      .post('/api/v1/admin/vehicles')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        flatId: otherFlatId,
        registeredUserId: many.body.data.user.id,
        vehicleType: 'FOUR_WHEELER',
        registrationNumber: 'MH12AB3002',
      });
    expect(wrongFlat.status).toBe(403);
    expect(wrongFlat.body.error.code).toBe('NOT_FLAT_OCCUPANT');
  });

  it('rolls back occupancy when a duplicate plate is submitted during assignment', async () => {
    const ctx = await createAdminContext(app, 'veh-dup-admin@example.com', 'VEH_DUP');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'D',
      flatRates: [4000, 4000],
    });
    const firstFlat = String(flats[0]._id);
    const secondFlat = String(flats[1]._id);

    const first = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'First Owner',
        email: 'first-veh@example.com',
        role: 'OWNER',
        username: 'firstveh',
        flatId: firstFlat,
        vehicles: [
          {
            vehicleType: 'FOUR_WHEELER',
            registrationNumber: 'KA03AB4444',
          },
        ],
      });
    expect(first.status).toBe(201);

    const second = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'Second Owner',
        email: 'second-veh@example.com',
        role: 'OWNER',
        username: 'secondveh',
        flatId: secondFlat,
        vehicles: [
          {
            vehicleType: 'FOUR_WHEELER',
            registrationNumber: 'KA03AB4444',
          },
        ],
      });
    expect(second.status).toBe(409);
    expect(second.body.error.code).toBe('DUPLICATE_VEHICLE');
    expect(await UserModel.findOne({ email: 'second-veh@example.com' })).toBeNull();
    expect(
      await OccupancyRecordModel.countDocuments({
        flatId: secondFlat,
        status: 'ACTIVE',
      }),
    ).toBe(0);
    expect(
      await VehicleModel.countDocuments({
        societyId: ctx.societyId,
        registrationNumber: 'KA03AB4444',
        isActive: true,
      }),
    ).toBe(1);

    const invalid = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'Bad Plate',
        email: 'badplate@example.com',
        role: 'OWNER',
        username: 'badplate',
        flatId: secondFlat,
        vehicles: [
          {
            vehicleType: 'TWO_WHEELER',
            registrationNumber: 'NOTAPLATER',
          },
        ],
      });
    expect(invalid.status).toBe(400);
    expect(invalid.body.error.code).toBe('INVALID_REGISTRATION_NUMBER');
    expect(await UserModel.findOne({ email: 'badplate@example.com' })).toBeNull();

    const sameRequest = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'Dup In Request',
        email: 'dup-in-request@example.com',
        role: 'OWNER',
        username: 'dupinreq',
        flatId: secondFlat,
        vehicles: [
          { vehicleType: 'FOUR_WHEELER', registrationNumber: 'MH12AB8888' },
          { vehicleType: 'TWO_WHEELER', registrationNumber: 'MH12AB8888' },
        ],
      });
    expect(sameRequest.status).toBe(409);
    expect(sameRequest.body.error.code).toBe('DUPLICATE_VEHICLE');
    expect(await UserModel.findOne({ email: 'dup-in-request@example.com' })).toBeNull();
  });

  it('lets admin add, edit, and deactivate vehicles for an assigned resident', async () => {
    const ctx = await createAdminContext(app, 'veh-edit-admin@example.com', 'VEH_EDT');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'E',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);

    const owner = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'Editable Owner',
        email: 'edit-veh@example.com',
        role: 'OWNER',
        username: 'editveh',
        flatId,
      });
    expect(owner.status).toBe(201);
    const userId = owner.body.data.user.id;

    const created = await request(app)
      .post('/api/v1/admin/vehicles')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        flatId,
        registeredUserId: userId,
        vehicleType: 'TWO_WHEELER',
        registrationNumber: 'DL1CAB5555',
        make: 'TVS',
      });
    expect(created.status).toBe(201);
    expect(created.body.data.registeredUserId).toBe(userId);
    expect(created.body.data.flatId).toBe(flatId);

    const patched = await request(app)
      .patch(`/api/v1/admin/vehicles/${created.body.data.id}`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        make: 'TVS',
        model: 'Jupiter',
        vehicleType: 'TWO_WHEELER',
        registrationNumber: 'DL1CAB5556',
      });
    expect(patched.status).toBe(200);
    expect(patched.body.data.model).toBe('Jupiter');
    expect(patched.body.data.registrationNumber).toBe('DL1CAB5556');
    expect(patched.body.data.registeredUserId).toBe(userId);
    expect(patched.body.data.flatId).toBe(flatId);

    const rejectRelink = await request(app)
      .patch(`/api/v1/admin/vehicles/${created.body.data.id}`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        registeredUserId: userId,
        flatId,
        model: 'Ntorq',
      });
    expect(rejectRelink.status).toBe(400);

    const deactivated = await request(app)
      .post(`/api/v1/admin/vehicles/${created.body.data.id}/deactivate`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ reason: 'Sold' });
    expect(deactivated.status).toBe(200);
    expect(deactivated.body.data.isActive).toBe(false);

    const existingResident = await createUser({
      email: 'self-reg-owner@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });
    const ownerToken = await login('self-reg-owner@example.com');
    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/end-owner-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'Handover' });
    const assignSelf = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        userId: String(existingResident._id),
        effectiveFrom: new Date().toISOString(),
        vehicles: [
          {
            vehicleType: 'FOUR_WHEELER',
            registrationNumber: 'GJ01AB7777',
            make: 'Tata',
            model: 'Nexon',
          },
        ],
      });
    expect(assignSelf.status).toBe(201);
    expect(assignSelf.body.data.vehicles).toHaveLength(1);

    const selfList = await request(app)
      .get('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId);
    expect(selfList.status).toBe(200);
    expect(selfList.body.data.items.some((v: { registrationNumber: string }) => v.registrationNumber === 'GJ01AB7777')).toBe(
      true,
    );

    const adminList = await request(app)
      .get('/api/v1/admin/vehicles')
      .query({ isActive: 'true' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(adminList.status).toBe(200);
    expect(
      adminList.body.data.items.some((v: { registrationNumber: string }) => v.registrationNumber === 'GJ01AB7777'),
    ).toBe(true);
  });
});
