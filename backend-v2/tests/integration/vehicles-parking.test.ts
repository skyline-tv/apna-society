import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginByEmail } from '../helpers/auth-login';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { VehicleModel } from '../../src/modules/vehicles/models/vehicle.model';
import { ParkingAllocationModel } from '../../src/modules/vehicles/models/parking-allocation.model';
import { VehicleLogModel } from '../../src/modules/vehicles/models/vehicle-log.model';
import { allocateParkingSlot } from '../../src/modules/vehicles/services/parking-allocation.service';

const app = createApp();

async function login(email: string) {
  const { token } = await loginByEmail(app, email);
  return token;
}

async function adminRegisterVehicle(
  token: string,
  body: {
    flatId: string;
    registeredUserId: string;
    vehicleType: string;
    registrationNumber: string;
    make?: string;
    model?: string;
    colour?: string;
    parkingNumber?: string;
  },
) {
  return request(app).post('/api/v1/admin/vehicles').set('Authorization', `Bearer ${token}`).send(body);
}

async function setupSociety(prefix: string) {
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
  const tenant = await createUser({
    email: `${prefix}-tenant@example.com`,
    roles: ['TENANT'],
    societyId: ctx.societyId,
  });

  await FlatModel.updateOne(
    { _id: flats[0]._id },
    { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
  );

  const guardRes = await request(app)
    .post('/api/v1/admin/guards')
    .set('Authorization', `Bearer ${ctx.token}`)
    .send({
      name: 'Gate Guard',
      email: `${prefix}-guard@example.com`,
      phone: '+91 9000000099',
      password: 'TestPassw0rd!',});
  expect(guardRes.status).toBe(201);

  const ownerToken = await login(`${prefix}-owner@example.com`);
  const tenantToken = await login(`${prefix}-tenant@example.com`);
  const guardToken = await login(`${prefix}-guard@example.com`);

  return {
    ctx,
    owner,
    tenant,
    flats,
    ownerToken,
    tenantToken,
    guardToken,
    ownerFlatId: String(flats[0]._id),
    vacantFlatId: String(flats[1]._id),
  };
}

describe('Resident vehicle visibility is read-only', () => {
  it('lets residents view their own vehicles and blocks add, edit, deactivate, and other residents', async () => {
    const setup = await setupSociety('veh');

    const ownerVehicle = await adminRegisterVehicle(setup.ctx.token, {
      flatId: setup.ownerFlatId,
      registeredUserId: String(setup.owner._id),
      vehicleType: 'FOUR_WHEELER',
      registrationNumber: 'MH 12 AB 1234',
      make: 'Honda',
      model: 'City',
    });
    expect(ownerVehicle.status).toBe(201);

    const residentCreate = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        vehicleType: 'TWO_WHEELER',
        registrationNumber: 'MH12CD5678',
      });
    expect(residentCreate.status).toBe(403);
    expect(residentCreate.body.error.code).toBe('RESIDENT_VEHICLE_READ_ONLY');

    const list = await request(app)
      .get('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(list.status).toBe(200);
    expect(list.body.data.items).toHaveLength(1);
    expect(list.body.data.items[0].registrationNumber).toBe('MH12AB1234');
    expect(list.body.data.items[0].vehicleType).toBe('FOUR_WHEELER');
    expect(list.body.data.items[0].make).toBe('Honda');
    expect(list.body.data.items[0].model).toBe('City');
    expect(list.body.data.items[0].flatNumber).toBe(setup.flats[0].number);
    expect(list.body.data.items[0].registeredUserId).toBe(String(setup.owner._id));

    const detail = await request(app)
      .get(`/api/v1/resident/vehicles/${ownerVehicle.body.data.id}`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(detail.status).toBe(200);
    expect(detail.body.data.flatNumber).toBe(setup.flats[0].number);

    const residentPatch = await request(app)
      .patch(`/api/v1/resident/vehicles/${ownerVehicle.body.data.id}`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({ make: 'Hero' });
    expect(residentPatch.status).toBe(403);
    expect(residentPatch.body.error.code).toBe('RESIDENT_VEHICLE_READ_ONLY');

    const residentDeactivate = await request(app)
      .post(`/api/v1/resident/vehicles/${ownerVehicle.body.data.id}/deactivate`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({ reason: 'Sold' });
    expect(residentDeactivate.status).toBe(403);
    expect(residentDeactivate.body.error.code).toBe('RESIDENT_VEHICLE_READ_ONLY');

    await FlatModel.updateOne(
      { _id: setup.flats[0]._id },
      {
        occupancyStatus: 'TENANT_OCCUPIED',
        activeOwnerUserId: setup.owner._id,
        activeTenantUserId: setup.tenant._id,
      },
    );
    const tenantVehicle = await adminRegisterVehicle(setup.ctx.token, {
      flatId: setup.ownerFlatId,
      registeredUserId: String(setup.tenant._id),
      vehicleType: 'TWO_WHEELER',
      registrationNumber: 'MH12CD5678',
      make: 'Honda',
      model: 'Activa',
    });
    expect(tenantVehicle.status).toBe(201);

    const tenantList = await request(app)
      .get('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.tenantToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(tenantList.status).toBe(200);
    expect(tenantList.body.data.items.map((v: { registrationNumber: string }) => v.registrationNumber)).toEqual([
      'MH12CD5678',
    ]);

    const tenantPeekOwner = await request(app)
      .get(`/api/v1/resident/vehicles/${ownerVehicle.body.data.id}`)
      .set('Authorization', `Bearer ${setup.tenantToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(tenantPeekOwner.status).toBe(404);

    const ownerStillSeesOwn = await request(app)
      .get('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(ownerStillSeesOwn.body.data.items.map((v: { registrationNumber: string }) => v.registrationNumber)).toEqual([
      'MH12AB1234',
    ]);

    const stranger = await createUser({
      email: 'vehl-stranger@example.com',
      roles: ['OWNER'],
      societyId: setup.ctx.societyId,
    });
    await FlatModel.updateOne(
      { _id: setup.flats[1]._id },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: stranger._id },
    );
    const strangerToken = await login('vehl-stranger@example.com');
    const peek = await request(app)
      .get(`/api/v1/resident/vehicles/${ownerVehicle.body.data.id}`)
      .set('Authorization', `Bearer ${strangerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(peek.status).toBe(404);

    const guardList = await request(app)
      .get('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(guardList.status).toBe(403);
  });

  it('lets admin add, edit, and deactivate vehicles after resident view is locked', async () => {
    const setup = await setupSociety('vehadm');
    const created = await adminRegisterVehicle(setup.ctx.token, {
      flatId: setup.ownerFlatId,
      registeredUserId: String(setup.owner._id),
      vehicleType: 'FOUR_WHEELER',
      registrationNumber: 'DL1CAA1234',
      make: 'Tata',
    });
    expect(created.status).toBe(201);

    const patched = await request(app)
      .patch(`/api/v1/admin/vehicles/${created.body.data.id}`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ model: 'Nexon' });
    expect(patched.status).toBe(200);
    expect(patched.body.data.model).toBe('Nexon');

    const duplicate = await adminRegisterVehicle(setup.ctx.token, {
      flatId: setup.ownerFlatId,
      registeredUserId: String(setup.owner._id),
      vehicleType: 'FOUR_WHEELER',
      registrationNumber: 'dl1caa1234',
    });
    expect(duplicate.status).toBe(409);
    expect(duplicate.body.error.code).toBe('DUPLICATE_VEHICLE');

    const deactivated = await request(app)
      .post(`/api/v1/admin/vehicles/${created.body.data.id}/deactivate`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ reason: 'Sold' });
    expect(deactivated.status).toBe(200);
    expect(deactivated.body.data.isActive).toBe(false);

    const stillThere = await VehicleModel.findById(created.body.data.id).lean();
    expect(stillThere?.isActive).toBe(false);
    expect(stillThere?.registrationNumber).toBe('DL1CAA1234');
  });

  it('deactivates a vehicle that still has a legacy parking allocation', async () => {
    const setup = await setupSociety('vehrel');
    const vehicle = await adminRegisterVehicle(setup.ctx.token, {
      flatId: setup.ownerFlatId,
      registeredUserId: String(setup.owner._id),
      vehicleType: 'FOUR_WHEELER',
      registrationNumber: 'MH12CD8899',
      parkingNumber: 'B-9',
    });
    expect(vehicle.status).toBe(201);

    const slot = await request(app)
      .post('/api/v1/admin/parking/slots')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ slotNumber: 'LEG-1', parkingType: 'FOUR_WHEELER' });
    expect(slot.status).toBe(201);

    const alloc = await request(app)
      .post('/api/v1/admin/parking/allocations')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        flatId: setup.ownerFlatId,
        vehicleId: vehicle.body.data.id,
        parkingSlotId: slot.body.data.id,
      });
    expect(alloc.status).toBe(201);

    const deactivated = await request(app)
      .post(`/api/v1/admin/vehicles/${vehicle.body.data.id}/deactivate`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ reason: 'Moved out' });
    expect(deactivated.status).toBe(200);
    expect(deactivated.body.data.isActive).toBe(false);
    expect(deactivated.body.error).toBeUndefined();

    const ended = await ParkingAllocationModel.findById(alloc.body.data.id).lean();
    expect(ended?.status).toBe('ENDED');
    expect(ended?.endReason).toBe('Moved out');
  });
});

describe('Parking slots and allocations', () => {
  it('creates slots, rejects duplicates, enforces compatibility, allocate/release, occupancy rules', async () => {
    const setup = await setupSociety('park');

    const slot = await request(app)
      .post('/api/v1/admin/parking/slots')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        slotNumber: 'B-101',
        parkingType: 'FOUR_WHEELER',
        locationDescription: 'Basement',
      });
    expect(slot.status).toBe(201);
    expect(slot.body.data.slotNumber).toBe('B-101');

    const dupSlot = await request(app)
      .post('/api/v1/admin/parking/slots')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ slotNumber: 'b-101', parkingType: 'TWO_WHEELER' });
    expect(dupSlot.status).toBe(409);

    const twoWheelerSlot = await request(app)
      .post('/api/v1/admin/parking/slots')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ slotNumber: 'T-01', parkingType: 'TWO_WHEELER' });
    expect(twoWheelerSlot.status).toBe(201);

    const vehicle = await adminRegisterVehicle(setup.ctx.token, {
      flatId: setup.ownerFlatId,
      registeredUserId: String(setup.owner._id),
      vehicleType: 'FOUR_WHEELER',
      registrationNumber: 'GJ01AB1001',
    });
    expect(vehicle.status).toBe(201);

    const badCompat = await request(app)
      .post('/api/v1/admin/parking/allocations')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        flatId: setup.ownerFlatId,
        vehicleId: vehicle.body.data.id,
        parkingSlotId: twoWheelerSlot.body.data.id,
      });
    expect(badCompat.status).toBe(400);
    expect(badCompat.body.error.code).toBe('INCOMPATIBLE_SLOT_TYPE');

    const alloc = await request(app)
      .post('/api/v1/admin/parking/allocations')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        flatId: setup.ownerFlatId,
        vehicleId: vehicle.body.data.id,
        parkingSlotId: slot.body.data.id,
      });
    expect(alloc.status).toBe(201);
    expect(alloc.body.data.status).toBe('ACTIVE');

    const dupSlotAlloc = await request(app)
      .post('/api/v1/admin/parking/allocations')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        flatId: setup.ownerFlatId,
        vehicleId: vehicle.body.data.id,
        parkingSlotId: slot.body.data.id,
      });
    expect(dupSlotAlloc.status).toBe(409);

    const vehicle2 = await adminRegisterVehicle(setup.ctx.token, {
      flatId: setup.ownerFlatId,
      registeredUserId: String(setup.owner._id),
      vehicleType: 'FOUR_WHEELER',
      registrationNumber: 'GJ01AB1002',
    });
    expect(vehicle2.status).toBe(201);

    const slot2 = await request(app)
      .post('/api/v1/admin/parking/slots')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ slotNumber: 'B-102', parkingType: 'FOUR_WHEELER' });
    expect(slot2.status).toBe(201);

    // Same vehicle cannot have two active allocations
    const dupVehicleAlloc = await request(app)
      .post('/api/v1/admin/parking/allocations')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        flatId: setup.ownerFlatId,
        vehicleId: vehicle.body.data.id,
        parkingSlotId: slot2.body.data.id,
      });
    expect(dupVehicleAlloc.status).toBe(409);

    const deactivateOccupied = await request(app)
      .post(`/api/v1/admin/parking/slots/${slot.body.data.id}/set-active`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ isActive: false, reason: 'Maintenance' });
    expect(deactivateOccupied.status).toBe(409);
    expect(deactivateOccupied.body.error.code).toBe('SLOT_OCCUPIED');

    const residentParking = await request(app)
      .get('/api/v1/resident/parking')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(residentParking.status).toBe(200);
    expect(residentParking.body.data.items).toHaveLength(1);
    expect(residentParking.body.data.items[0].slot.slotNumber).toBe('B-101');

    const release = await request(app)
      .post(`/api/v1/admin/parking/allocations/${alloc.body.data.id}/release`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ reason: 'Moved out' });
    expect(release.status).toBe(200);
    expect(release.body.data.status).toBe('ENDED');

    const history = await ParkingAllocationModel.findById(alloc.body.data.id).lean();
    expect(history?.status).toBe('ENDED');
    expect(history?.endsAt).toBeTruthy();

    const summary = await request(app)
      .get('/api/v1/admin/parking/summary')
      .set('Authorization', `Bearer ${setup.ctx.token}`);
    expect(summary.status).toBe(200);
    expect(summary.body.data.occupiedSlots).toBe(0);

    const other = await createAdminContext(app, 'park-other@example.com', 'PARKX');
    const { flats: otherFlats } = await createWingWithFlats({
      societyId: other.societyId,
      code: 'Z',
      flatRates: [4000],
    });
    const crossAlloc = await request(app)
      .post('/api/v1/admin/parking/allocations')
      .set('Authorization', `Bearer ${other.token}`)
      .send({
        flatId: String(otherFlats[0]._id),
        vehicleId: vehicle.body.data.id,
        parkingSlotId: slot2.body.data.id,
      });
    expect([400, 404]).toContain(crossAlloc.status);

    const guardAlloc = await request(app)
      .post('/api/v1/admin/parking/allocations')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        flatId: setup.ownerFlatId,
        vehicleId: vehicle2.body.data.id,
        parkingSlotId: slot2.body.data.id,
      });
    expect(guardAlloc.status).toBe(403);
  });

  it('rejects concurrent allocations of the same slot', async () => {
    const setup = await setupSociety('conc');
    const slot = await request(app)
      .post('/api/v1/admin/parking/slots')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ slotNumber: 'C-01', parkingType: 'FOUR_WHEELER' });
    expect(slot.status).toBe(201);

    const v1 = await adminRegisterVehicle(setup.ctx.token, {
      flatId: setup.ownerFlatId,
      registeredUserId: String(setup.owner._id),
      vehicleType: 'FOUR_WHEELER',
      registrationNumber: 'TN09AB1111',
    });
    const v2 = await adminRegisterVehicle(setup.ctx.token, {
      flatId: setup.ownerFlatId,
      registeredUserId: String(setup.owner._id),
      vehicleType: 'FOUR_WHEELER',
      registrationNumber: 'TN09AB2222',
    });
    expect(v1.status).toBe(201);
    expect(v2.status).toBe(201);

    const actor = { userId: setup.ctx.userId };
    const results = await Promise.allSettled([
      allocateParkingSlot(
        setup.ctx.societyId,
        {
          flatId: setup.ownerFlatId,
          vehicleId: v1.body.data.id,
          parkingSlotId: slot.body.data.id,
        },
        actor,
      ),
      allocateParkingSlot(
        setup.ctx.societyId,
        {
          flatId: setup.ownerFlatId,
          vehicleId: v2.body.data.id,
          parkingSlotId: slot.body.data.id,
        },
        actor,
      ),
    ]);

    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');
    expect(fulfilled).toHaveLength(1);
    expect(rejected).toHaveLength(1);

    const activeCount = await ParkingAllocationModel.countDocuments({
      parkingSlotId: slot.body.data.id,
      status: 'ACTIVE',
    });
    expect(activeCount).toBe(1);
  });
});

describe('Guard vehicle logs', () => {
  it('records entry/exit, rejects duplicate active entry, preserves history, blocks cross-society and allocation edits', async () => {
    const setup = await setupSociety('vlog');

    const registered = await adminRegisterVehicle(setup.ctx.token, {
      flatId: setup.ownerFlatId,
      registeredUserId: String(setup.owner._id),
      vehicleType: 'FOUR_WHEELER',
      registrationNumber: 'KA05MZ4321',
    });
    expect(registered.status).toBe(201);

    const entry = await request(app)
      .post('/api/v1/guard/vehicles/entry')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        registrationNumber: 'KA05MZ4321',
        vehicleId: registered.body.data.id,
      });
    expect(entry.status).toBe(201);
    expect(entry.body.data.status).toBe('INSIDE');
    expect(entry.body.data.isRegisteredResidentVehicle).toBe(true);

    const dupEntry = await request(app)
      .post('/api/v1/guard/vehicles/entry')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({ registrationNumber: 'KA 05 MZ 4321' });
    expect(dupEntry.status).toBe(409);

    const visitorEntry = await request(app)
      .post('/api/v1/guard/vehicles/entry')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        registrationNumber: 'MH14ZZ9999',
        vehicleType: 'FOUR_WHEELER',
        notes: 'Visitor guest car',
      });
    expect(visitorEntry.status).toBe(201);
    expect(visitorEntry.body.data.isRegisteredResidentVehicle).toBe(false);
    expect(visitorEntry.body.data.vehicleId).toBeUndefined();

    const visitorVehicleCount = await VehicleModel.countDocuments({
      registrationNumber: 'MH14ZZ9999',
    });
    expect(visitorVehicleCount).toBe(0);

    const exit = await request(app)
      .post('/api/v1/guard/vehicles/exit')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({ logId: entry.body.data.id });
    expect(exit.status).toBe(200);
    expect(exit.body.data.status).toBe('EXITED');

    const reEntry = await request(app)
      .post('/api/v1/guard/vehicles/entry')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({ registrationNumber: 'KA05MZ4321' });
    expect(reEntry.status).toBe(201);

    const logs = await request(app)
      .get('/api/v1/guard/vehicles/logs')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .query({ registrationNumber: 'KA05MZ4321' });
    expect(logs.status).toBe(200);
    expect(logs.body.data.items.length).toBeGreaterThanOrEqual(2);
    expect(logs.body.data.items.some((l: { status: string }) => l.status === 'EXITED')).toBe(true);

    const historyCount = await VehicleLogModel.countDocuments({
      societyId: setup.ctx.societyId,
      registrationNumber: 'KA05MZ4321',
    });
    expect(historyCount).toBe(2);

    const other = await createAdminContext(app, 'vlog-other@example.com', 'VLOGX');
    const otherGuard = await request(app)
      .post('/api/v1/admin/guards')
      .set('Authorization', `Bearer ${other.token}`)
      .send({ name: 'Other Guard', email: 'vlog-other-guard@example.com',
      password: 'TestPassw0rd!',});
    expect(otherGuard.status).toBe(201);
    const otherGuardToken = await login('vlog-other-guard@example.com');
    const cross = await request(app)
      .get('/api/v1/guard/vehicles/logs')
      .set('Authorization', `Bearer ${otherGuardToken}`);
    expect(cross.status).toBe(200);
    expect(cross.body.data.items).toHaveLength(0);

    const guardSlot = await request(app)
      .post('/api/v1/admin/parking/slots')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({ slotNumber: 'HACK', parkingType: 'FOUR_WHEELER' });
    expect(guardSlot.status).toBe(403);
  });

  it('assigns a parking number on the vehicle without payment fields', async () => {
    const setup = await setupSociety('vparknum');
    const created = await adminRegisterVehicle(setup.ctx.token, {
      flatId: setup.ownerFlatId,
      registeredUserId: String(setup.owner._id),
      vehicleType: 'TWO_WHEELER',
      registrationNumber: 'MH14CD7788',
      parkingNumber: 'TW-12',
    });
    expect(created.status).toBe(201);
    expect(created.body.data.parkingNumber).toBe('TW-12');
    expect(created.body.data.amountPaise).toBeUndefined();
    expect(created.body.data.paymentStatus).toBeUndefined();

    const second = await adminRegisterVehicle(setup.ctx.token, {
      flatId: setup.ownerFlatId,
      registeredUserId: String(setup.owner._id),
      vehicleType: 'FOUR_WHEELER',
      registrationNumber: 'MH14CD7799',
      parkingNumber: 'B-3',
    });
    expect(second.status).toBe(201);
    expect(second.body.data.flatId).toBe(setup.ownerFlatId);
    expect(second.body.data.registeredUserId).toBe(String(setup.owner._id));

    const patched = await request(app)
      .patch(`/api/v1/admin/vehicles/${created.body.data.id}`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ parkingNumber: 'TW-14' });
    expect(patched.status).toBe(200);
    expect(patched.body.data.parkingNumber).toBe('TW-14');

    const listed = await request(app)
      .get('/api/v1/admin/vehicles')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .query({ flatId: setup.ownerFlatId, isActive: 'true' });
    expect(listed.status).toBe(200);
    expect(listed.body.data.items).toHaveLength(2);
    expect(listed.body.data.items.map((v: { parkingNumber: string }) => v.parkingNumber)).toEqual(
      expect.arrayContaining(['TW-14', 'B-3']),
    );
  });
});
