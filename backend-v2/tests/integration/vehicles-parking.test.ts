import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginByEmail } from '../helpers/auth-login';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { MembershipModel } from '../../src/modules/users/models/membership.model';
import { VehicleModel } from '../../src/modules/vehicles/models/vehicle.model';
import { ParkingAllocationModel } from '../../src/modules/vehicles/models/parking-allocation.model';
import { VehicleLogModel } from '../../src/modules/vehicles/models/vehicle-log.model';
import { allocateParkingSlot } from '../../src/modules/vehicles/services/parking-allocation.service';

const app = createApp();

async function login(email: string) {
  const { token } = await loginByEmail(app, email);
  return token;
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
    });
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

describe('Resident vehicle registration', () => {
  it('allows owner and active tenant; blocks owner-with-tenant, previous tenant, inactive, guard, duplicates, cross-society', async () => {
    const setup = await setupSociety('veh');

    const ownerReg = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        vehicleType: 'FOUR_WHEELER',
        registrationNumber: 'MH 12 AB 1234',
        make: 'Honda',
        colour: 'White',
      });
    expect(ownerReg.status).toBe(201);
    expect(ownerReg.body.data.registrationNumber).toBe('MH12AB1234');
    expect(ownerReg.body.data.isActive).toBe(true);

    const dup = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        vehicleType: 'FOUR_WHEELER',
        registrationNumber: 'mh12-ab-1234',
      });
    expect(dup.status).toBe(409);
    expect(dup.body.error.code).toBe('DUPLICATE_VEHICLE');

    await FlatModel.updateOne(
      { _id: setup.flats[0]._id },
      {
        occupancyStatus: 'TENANT_OCCUPIED',
        activeOwnerUserId: setup.owner._id,
        activeTenantUserId: setup.tenant._id,
      },
    );

    const ownerBlocked = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        vehicleType: 'TWO_WHEELER',
        registrationNumber: 'MH12CD5678',
      });
    expect(ownerBlocked.status).toBe(403);
    expect(ownerBlocked.body.error.code).toBe('RESIDENTIAL_ACCESS_DENIED');

    const tenantReg = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.tenantToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        vehicleType: 'TWO_WHEELER',
        registrationNumber: 'MH12CD5678',
      });
    expect(tenantReg.status).toBe(201);

    await FlatModel.updateOne(
      { _id: setup.flats[0]._id },
      {
        occupancyStatus: 'OWNER_OCCUPIED',
        activeOwnerUserId: setup.owner._id,
        activeTenantUserId: null,
      },
    );

    const previousTenant = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.tenantToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        vehicleType: 'OTHER',
        registrationNumber: 'MH12EF9012',
      });
    expect(previousTenant.status).toBe(403);

    await MembershipModel.updateOne(
      { userId: setup.owner._id, societyId: setup.ctx.societyId },
      { isActive: false },
    );
    const inactiveOwner = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        vehicleType: 'OTHER',
        registrationNumber: 'MH12EF9012',
      });
    expect([403, 401]).toContain(inactiveOwner.status);
    await MembershipModel.updateOne(
      { userId: setup.owner._id, societyId: setup.ctx.societyId },
      { isActive: true },
    );

    const guardReg = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        vehicleType: 'FOUR_WHEELER',
        registrationNumber: 'MH12GH3456',
      });
    expect(guardReg.status).toBe(403);

    const other = await createAdminContext(app, 'veh-other@example.com', 'VEHX');
    const { flats: otherFlats } = await createWingWithFlats({
      societyId: other.societyId,
      code: 'X',
      flatRates: [4000],
    });
    const otherOwner = await createUser({
      email: 'veh-other-owner@example.com',
      roles: ['OWNER'],
      societyId: other.societyId,
    });
    await FlatModel.updateOne(
      { _id: otherFlats[0]._id },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: otherOwner._id },
    );
    const otherToken = await login('veh-other-owner@example.com');
    const cross = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${otherToken}`)
      .set('x-society-id', other.societyId)
      .send({
        flatId: setup.ownerFlatId,
        vehicleType: 'FOUR_WHEELER',
        registrationNumber: 'KA01AB9999',
      });
    expect([403, 404]).toContain(cross.status);

    const vehicleId = ownerReg.body.data.id as string;
    const deactivate = await request(app)
      .post(`/api/v1/resident/vehicles/${vehicleId}/deactivate`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({ reason: 'Sold' });
    expect(deactivate.status).toBe(200);
    expect(deactivate.body.data.isActive).toBe(false);

    const stillThere = await VehicleModel.findById(vehicleId).lean();
    expect(stillThere).toBeTruthy();
    expect(stillThere!.isActive).toBe(false);
    expect(stillThere!.registrationNumber).toBe('MH12AB1234');
  });

  it('lists only residential-accessible vehicles and blocks peering at other flats', async () => {
    const setup = await setupSociety('vehl');
    const created = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        vehicleType: 'FOUR_WHEELER',
        registrationNumber: 'DL1CAA1234',
      });
    expect(created.status).toBe(201);

    const list = await request(app)
      .get('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(list.status).toBe(200);
    expect(list.body.data.items).toHaveLength(1);

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
      .get(`/api/v1/resident/vehicles/${created.body.data.id}`)
      .set('Authorization', `Bearer ${strangerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(peek.status).toBe(403);
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

    const vehicle = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
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

    const vehicle2 = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
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

    const v1 = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        vehicleType: 'FOUR_WHEELER',
        registrationNumber: 'TN09AB1111',
      });
    const v2 = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
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

    const registered = await request(app)
      .post('/api/v1/resident/vehicles')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
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
      .send({ name: 'Other Guard', email: 'vlog-other-guard@example.com' });
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
});
