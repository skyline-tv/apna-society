import { describe, expect, it, beforeEach } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginByEmail } from '../helpers/auth-login';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { UserModel } from '../../src/modules/users/models/user.model';
import { MembershipModel } from '../../src/modules/users/models/membership.model';
import { StaffModel } from '../../src/modules/staff/models/staff.model';
import { StaffAttendanceModel } from '../../src/modules/staff/models/staff-attendance.model';
import { FacilityBookingModel } from '../../src/modules/facilities/models/facility-booking.model';
import { createShift } from '../../src/modules/staff/services/shift.service';
import {
  approveBooking,
  createBooking,
} from '../../src/modules/facilities/services/booking.service';
import {
  setFacilityEventEmitterForTests,
  type FacilityBookingEventPayload,
  type FacilitySocketEvent,
} from '../../src/modules/facilities/services/facility-events.service';
import { resetEnvCache, loadEnv } from '../../src/config/env';
import { addCivilDays, localDateString } from '../../src/modules/staff/utils/society-time';

const app = createApp();

async function login(email: string) {
  const { token } = await loginByEmail(app, email);
  return token;
}

async function setup(prefix: string) {
  const ctx = await createAdminContext(app, `${prefix}-admin@example.com`, prefix.toUpperCase());
  const { flats } = await createWingWithFlats({
    societyId: ctx.societyId,
    code: 'F',
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
    .send({ name: 'Gate', email: `${prefix}-guard@example.com`, phone: '+919876500001' });
  expect(guardRes.status).toBe(201);

  return {
    ctx,
    owner,
    tenant,
    flats,
    ownerToken: await login(`${prefix}-owner@example.com`),
    tenantToken: await login(`${prefix}-tenant@example.com`),
    guardToken: await login(`${prefix}-guard@example.com`),
    guardId: guardRes.body.data.guard.id as string,
    flatId: String(flats[0]._id),
  };
}

describe('Staff management', () => {
  it('creates/updates staff, rejects duplicate phone, links guard without role duplication', async () => {
    const s = await setup('stf');
    const created = await request(app)
      .post('/api/v1/admin/staff')
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({
        fullName: 'Ramesh Security',
        phone: '+91 98765 43210',
        category: 'SECURITY',
        employmentType: 'PERMANENT',
        joiningDate: '2026-01-15',
        linkedUserId: s.guardId,
      });
    expect(created.status).toBe(201);
    expect(created.body.data.linkedUserId).toBe(s.guardId);

    const guardUser = await UserModel.findById(s.guardId).lean();
    expect(guardUser?.roles.filter((r) => r === 'GUARD')).toHaveLength(1);
    const guardMemberships = await MembershipModel.countDocuments({
      societyId: s.ctx.societyId,
      userId: s.guardId,
      role: 'GUARD',
      isActive: true,
    });
    expect(guardMemberships).toBe(1);

    const dup = await request(app)
      .post('/api/v1/admin/staff')
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({
        fullName: 'Other',
        phone: '+919876543210',
        category: 'HOUSEKEEPING',
        employmentType: 'CONTRACT',
        joiningDate: '2026-02-01',
      });
    expect(dup.status).toBe(409);

    const other = await createAdminContext(app, 'stf-other@example.com', 'STFX');
    const cross = await request(app)
      .get(`/api/v1/admin/staff/${created.body.data.id}`)
      .set('Authorization', `Bearer ${other.token}`);
    expect(cross.status).toBe(404);

    await request(app)
      .post(`/api/v1/admin/staff/${created.body.data.id}/deactivate`)
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({ reason: 'Leave' });
    const still = await StaffModel.findById(created.body.data.id).lean();
    expect(still?.employmentStatus).toBe('INACTIVE');

    await request(app)
      .post(`/api/v1/admin/staff/${created.body.data.id}/terminate`)
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({ reason: 'Left' });

    const shiftDenied = await request(app)
      .post('/api/v1/admin/staff-shifts')
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({
        staffId: created.body.data.id,
        shiftDate: addCivilDays(localDateString(new Date(), 'Asia/Kolkata'), 2),
        startTime: '09:00',
        endTime: '17:00',
      });
    expect(shiftDenied.status).toBe(400);
  });
});

describe('Attendance and shifts', () => {
  it('enforces one attendance/day, checkout, corrections, overlaps and overnight shifts', async () => {
    const s = await setup('att');
    const staff = await request(app)
      .post('/api/v1/admin/staff')
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({
        fullName: 'Housekeeper',
        phone: '+919800011122',
        category: 'HOUSEKEEPING',
        employmentType: 'TEMPORARY',
        joiningDate: '2026-03-01',
      });
    expect(staff.status).toBe(201);
    const staffId = staff.body.data.id as string;
    const today = localDateString(new Date(), 'Asia/Kolkata');

    const marked = await request(app)
      .post('/api/v1/admin/staff-attendance')
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({ staffId, status: 'PRESENT', localDate: today });
    expect(marked.status).toBe(201);

    const dup = await request(app)
      .post('/api/v1/admin/staff-attendance')
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({ staffId, status: 'ABSENT', localDate: today });
    expect(dup.status).toBe(409);

    const checkout = await request(app)
      .post(`/api/v1/admin/staff-attendance/${marked.body.data.id}/checkout`)
      .set('Authorization', `Bearer ${s.ctx.token}`);
    expect(checkout.status).toBe(200);
    expect(checkout.body.data.checkOutAt).toBeTruthy();

    const dupCheckout = await request(app)
      .post(`/api/v1/admin/staff-attendance/${marked.body.data.id}/checkout`)
      .set('Authorization', `Bearer ${s.ctx.token}`);
    expect(dupCheckout.status).toBe(409);

    const corrected = await request(app)
      .post(`/api/v1/admin/staff-attendance/${marked.body.data.id}/correct`)
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({ status: 'HALF_DAY', reason: 'Left early' });
    expect(corrected.status).toBe(200);
    expect(corrected.body.data.correctionHistory).toHaveLength(1);

    const inactive = await request(app)
      .post(`/api/v1/admin/staff/${staffId}/deactivate`)
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({});
    expect(inactive.status).toBe(200);
    const attInactive = await request(app)
      .post('/api/v1/admin/staff-attendance')
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({
        staffId,
        status: 'PRESENT',
        localDate: addCivilDays(today, 1),
      });
    expect(attInactive.status).toBe(400);

    await request(app)
      .post(`/api/v1/admin/staff/${staffId}/reactivate`)
      .set('Authorization', `Bearer ${s.ctx.token}`);

    const future = addCivilDays(today, 3);
    const shift = await request(app)
      .post('/api/v1/admin/staff-shifts')
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({
        staffId,
        shiftDate: future,
        startTime: '22:00',
        endTime: '06:00',
        dutyLocation: 'Gate A',
      });
    expect(shift.status).toBe(201);
    expect(new Date(shift.body.data.endAt).getTime()).toBeGreaterThan(
      new Date(shift.body.data.startAt).getTime(),
    );

    const overlap = await request(app)
      .post('/api/v1/admin/staff-shifts')
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({
        staffId,
        shiftDate: future,
        startTime: '23:00',
        endTime: '05:00',
      });
    expect(overlap.status).toBe(409);

    const actor = { userId: s.ctx.userId };
    const results = await Promise.allSettled([
      createShift(
        s.ctx.societyId,
        { staffId, shiftDate: addCivilDays(today, 5), startTime: '09:00', endTime: '13:00' },
        actor,
      ),
      createShift(
        s.ctx.societyId,
        { staffId, shiftDate: addCivilDays(today, 5), startTime: '11:00', endTime: '15:00' },
        actor,
      ),
    ]);
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    expect(results.filter((r) => r.status === 'rejected')).toHaveLength(1);

    // Guards cannot manage attendance by default
    const guardAtt = await request(app)
      .post('/api/v1/admin/staff-attendance')
      .set('Authorization', `Bearer ${s.guardToken}`)
      .send({ staffId, status: 'PRESENT', localDate: addCivilDays(today, 2) });
    expect(guardAtt.status).toBe(403);

    expect(await StaffAttendanceModel.countDocuments({ staffId })).toBeGreaterThanOrEqual(1);
  });
});

describe('Facility bookings', () => {
  const events: Array<{
    event: FacilitySocketEvent;
    rooms: string[];
    payload: FacilityBookingEventPayload;
  }> = [];

  beforeEach(() => {
    events.length = 0;
    setFacilityEventEmitterForTests((event, rooms, payload) => {
      events.push({ event, rooms, payload });
    });
  });

  it('enforces residential access, capacity, pending expiry, fees unpaid, notifications', async () => {
    const s = await setup('fac');
    const facility = await request(app)
      .post('/api/v1/admin/facilities')
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({
        name: 'Clubhouse',
        category: 'CLUBHOUSE',
        capacity: 1,
        maxBookingDurationMinutes: 120,
        openingTime: '08:00',
        closingTime: '22:00',
        availableDays: [
          'MONDAY',
          'TUESDAY',
          'WEDNESDAY',
          'THURSDAY',
          'FRIDAY',
          'SATURDAY',
          'SUNDAY',
        ],
        bookingFeePaise: 50000,
        requiresApproval: true,
      });
    expect(facility.status).toBe(201);
    const facilityId = facility.body.data.id as string;
    expect(facility.body.data.feePaymentRequired).toBe(true);

    const bookingDate = addCivilDays(localDateString(new Date(), 'Asia/Kolkata'), 7);

    const created = await request(app)
      .post(`/api/v1/resident/facilities/${facilityId}/bookings`)
      .set('Authorization', `Bearer ${s.ownerToken}`)
      .set('x-society-id', s.ctx.societyId)
      .send({
        flatId: s.flatId,
        bookingDate,
        startTime: '10:00',
        endTime: '12:00',
      });
    expect(created.status).toBe(201);
    expect(created.body.data.status).toBe('PENDING');
    expect(created.body.data.feePaid).toBe(false);
    expect(created.body.data.feePaymentRequired).toBe(true);
    expect(created.body.data.adminNotes).toBeUndefined();

    await FlatModel.updateOne(
      { _id: s.flats[0]._id },
      {
        occupancyStatus: 'TENANT_OCCUPIED',
        activeOwnerUserId: s.owner._id,
        activeTenantUserId: s.tenant._id,
      },
    );
    const ownerBlocked = await request(app)
      .post(`/api/v1/resident/facilities/${facilityId}/bookings`)
      .set('Authorization', `Bearer ${s.ownerToken}`)
      .set('x-society-id', s.ctx.societyId)
      .send({
        flatId: s.flatId,
        bookingDate,
        startTime: '14:00',
        endTime: '16:00',
      });
    expect(ownerBlocked.status).toBe(403);

    const tenantBooking = await request(app)
      .post(`/api/v1/resident/facilities/${facilityId}/bookings`)
      .set('Authorization', `Bearer ${s.tenantToken}`)
      .set('x-society-id', s.ctx.societyId)
      .send({
        flatId: s.flatId,
        bookingDate,
        startTime: '14:00',
        endTime: '16:00',
      });
    expect(tenantBooking.status).toBe(201);

    await FlatModel.updateOne(
      { _id: s.flats[0]._id },
      {
        occupancyStatus: 'OWNER_OCCUPIED',
        activeOwnerUserId: s.owner._id,
        activeTenantUserId: null,
      },
    );
    const prevTenant = await request(app)
      .get(`/api/v1/resident/facility-bookings/${tenantBooking.body.data.id}`)
      .set('Authorization', `Bearer ${s.tenantToken}`)
      .set('x-society-id', s.ctx.societyId);
    expect(prevTenant.status).toBe(403);

    const approved = await request(app)
      .post(`/api/v1/admin/facility-bookings/${created.body.data.id}/approve`)
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({ adminNotes: 'Internal only' });
    expect(approved.status).toBe(200);
    expect(approved.body.data.status).toBe('CONFIRMED');
    expect(approved.body.data.feePaid).toBe(false);
    expect(events.some((e) => e.event === 'facility:booking_approved')).toBe(true);

    const residentView = await request(app)
      .get(`/api/v1/resident/facility-bookings/${created.body.data.id}`)
      .set('Authorization', `Bearer ${s.ownerToken}`)
      .set('x-society-id', s.ctx.societyId);
    expect(residentView.body.data.adminNotes).toBeUndefined();
    expect(JSON.stringify(residentView.body)).not.toContain('Internal only');

    // Capacity-one conflict on overlapping approve
    const pending2 = await request(app)
      .post(`/api/v1/resident/facilities/${facilityId}/bookings`)
      .set('Authorization', `Bearer ${s.ownerToken}`)
      .set('x-society-id', s.ctx.societyId)
      .send({
        flatId: s.flatId,
        bookingDate,
        startTime: '11:00',
        endTime: '13:00',
      });
    expect(pending2.status).toBe(201);
    const conflictApprove = await request(app)
      .post(`/api/v1/admin/facility-bookings/${pending2.body.data.id}/approve`)
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({});
    expect(conflictApprove.status).toBe(409);

    // Capacity > 1 concurrent approvals
    const gym = await request(app)
      .post('/api/v1/admin/facilities')
      .set('Authorization', `Bearer ${s.ctx.token}`)
      .send({
        name: 'Gym',
        category: 'GYM',
        capacity: 2,
        maxBookingDurationMinutes: 60,
        openingTime: '06:00',
        closingTime: '21:00',
        availableDays: [
          'MONDAY',
          'TUESDAY',
          'WEDNESDAY',
          'THURSDAY',
          'FRIDAY',
          'SATURDAY',
          'SUNDAY',
        ],
        requiresApproval: true,
        bookingFeePaise: 0,
      });
    const gymId = gym.body.data.id as string;
    const gymDate = addCivilDays(bookingDate, 1);
    const actor = { userId: s.ctx.userId };
    const b1 = await createBooking(
      s.ctx.societyId,
      String(s.owner._id),
      gymId,
      { flatId: s.flatId, bookingDate: gymDate, startTime: '07:00', endTime: '08:00' },
      actor,
    );
    const b2 = await createBooking(
      s.ctx.societyId,
      String(s.owner._id),
      gymId,
      { flatId: s.flatId, bookingDate: gymDate, startTime: '07:15', endTime: '08:15' },
      actor,
    );
    const b3 = await createBooking(
      s.ctx.societyId,
      String(s.owner._id),
      gymId,
      { flatId: s.flatId, bookingDate: gymDate, startTime: '07:30', endTime: '08:30' },
      actor,
    );
    const approvals = await Promise.allSettled([
      approveBooking(s.ctx.societyId, b1.id, undefined, actor),
      approveBooking(s.ctx.societyId, b2.id, undefined, actor),
      approveBooking(s.ctx.societyId, b3.id, undefined, actor),
    ]);
    expect(approvals.filter((r) => r.status === 'fulfilled')).toHaveLength(2);
    expect(approvals.filter((r) => r.status === 'rejected')).toHaveLength(1);
    const confirmed = await FacilityBookingModel.countDocuments({
      facilityId: gymId,
      status: 'CONFIRMED',
    });
    expect(confirmed).toBe(2);

    // Pending expiry
    process.env.FACILITY_PENDING_BOOKING_TTL_MS = '1';
    resetEnvCache();
    loadEnv();
    const shortPending = await createBooking(
      s.ctx.societyId,
      String(s.owner._id),
      gymId,
      {
        flatId: s.flatId,
        bookingDate: addCivilDays(gymDate, 2),
        startTime: '09:00',
        endTime: '10:00',
      },
      actor,
    );
    await new Promise((r) => setTimeout(r, 5));
    await FacilityBookingModel.updateOne(
      { _id: shortPending.id },
      { expiresAt: new Date(Date.now() - 1000) },
    );
    const avail = await request(app)
      .get(`/api/v1/resident/facilities/${gymId}/availability`)
      .set('Authorization', `Bearer ${s.ownerToken}`)
      .set('x-society-id', s.ctx.societyId)
      .query({ date: addCivilDays(gymDate, 2) });
    expect(avail.status).toBe(200);
    const expired = await FacilityBookingModel.findById(shortPending.id).lean();
    expect(expired?.status).toBe('CANCELLED');
    process.env.FACILITY_PENDING_BOOKING_TTL_MS = '3600000';
    resetEnvCache();
    loadEnv();

    const other = await createAdminContext(app, 'fac-other@example.com', 'FACX');
    const crossFac = await request(app)
      .get(`/api/v1/admin/facilities/${facilityId}`)
      .set('Authorization', `Bearer ${other.token}`);
    expect(crossFac.status).toBe(404);

    const guardBook = await request(app)
      .post(`/api/v1/resident/facilities/${facilityId}/bookings`)
      .set('Authorization', `Bearer ${s.guardToken}`)
      .set('x-society-id', s.ctx.societyId)
      .send({
        flatId: s.flatId,
        bookingDate: addCivilDays(bookingDate, 3),
        startTime: '10:00',
        endTime: '11:00',
      });
    expect(guardBook.status).toBe(403);
  });
});
