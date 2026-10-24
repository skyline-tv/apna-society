/**
 * Launch reset: wipe accounts, bills, collections and other operational data.
 * Keeps society, wings, flats and maintenance rates. Vacates every flat.
 *
 * Usage:
 *   npm run reset:launch -- --confirm
 */
import { loadEnv } from '../src/config/env';
import { connectDatabase, disconnectDatabase } from '../src/database/connection';
import { hashPassword } from '../src/utils/password';
import { normalizeEmail } from '../src/utils/crypto';
import { assertValidUsername } from '../src/utils/username';
import { UserModel } from '../src/modules/users/models/user.model';
import { MembershipModel } from '../src/modules/users/models/membership.model';
import { SocietyModel } from '../src/modules/society/models/society.model';
import { WingModel } from '../src/modules/society/models/wing.model';
import { FlatModel } from '../src/modules/society/models/flat.model';
import { OccupancyRecordModel } from '../src/modules/society/models/occupancy-record.model';
import { BillModel } from '../src/modules/billing/models/bill.model';
import { PaymentModel } from '../src/modules/billing/models/payment.model';
import { ReceiptModel } from '../src/modules/billing/models/receipt.model';
import { FlatAdditionalServiceModel } from '../src/modules/billing/models/additional-service.model';
import { PrincipalLedgerModel } from '../src/modules/billing/models/principal-ledger.model';
import { InterestJobRunModel } from '../src/modules/billing/models/interest-job-run.model';
import { SequenceModel } from '../src/modules/billing/models/sequence.model';
import { CollectionModel } from '../src/modules/collections/models/collection.model';
import { CollectionChargeModel } from '../src/modules/collections/models/collection-charge.model';
import { CollectionPaymentModel } from '../src/modules/collections/models/collection-payment.model';
import { CollectionReceiptModel } from '../src/modules/collections/models/collection-receipt.model';
import { CollectionAdjustmentModel } from '../src/modules/collections/models/collection-adjustment.model';
import { RefreshSessionModel } from '../src/modules/auth/models/refresh-session.model';
import { OtpChallengeModel } from '../src/modules/auth/models/otp-challenge.model';
import { AuditLogModel } from '../src/modules/auth/models/audit-log.model';
import { NotificationModel } from '../src/modules/notifications/models/notification.model';
import { DeviceTokenModel } from '../src/modules/notifications/models/device-token.model';
import { VisitorLogModel } from '../src/modules/visitors/models/visitor-log.model';
import { ParcelHandoverModel } from '../src/modules/visitors/models/parcel-handover.model';
import { VehicleModel } from '../src/modules/vehicles/models/vehicle.model';
import { VehicleLogModel } from '../src/modules/vehicles/models/vehicle-log.model';
import { ParkingAllocationModel } from '../src/modules/vehicles/models/parking-allocation.model';
import { ParkingSlotModel } from '../src/modules/vehicles/models/parking-slot.model';
import { ComplaintModel } from '../src/modules/complaints/models/complaint.model';
import { ComplaintHistoryModel } from '../src/modules/complaints/models/complaint-history.model';
import { AnnouncementModel } from '../src/modules/announcements/models/announcement.model';
import { AnnouncementReadModel } from '../src/modules/announcements/models/announcement-read.model';
import { StaffModel } from '../src/modules/staff/models/staff.model';
import { StaffShiftModel } from '../src/modules/staff/models/staff-shift.model';
import { StaffAttendanceModel } from '../src/modules/staff/models/staff-attendance.model';
import { FacilityModel } from '../src/modules/facilities/models/facility.model';
import { FacilityBookingModel } from '../src/modules/facilities/models/facility-booking.model';

const SOCIETY_CODE = 'MONARCH_SOLITAIRE';

const ADMINS = [
  {
    username: 'sltv',
    password: 'Sltv@12345',
    email: 'skylinetechventures@gmail.com',
    name: 'SLTV',
    mustChangePassword: false,
  },
  {
    username: 'admin',
    password: 'Admin@12345',
    email: 'monarchsolitaire@gmail.com',
    name: 'Monarch Solitaire Admin',
    mustChangePassword: true,
  },
] as const;

async function wipeOperationalData(): Promise<Record<string, number>> {
  const jobs: Array<[string, Promise<{ deletedCount?: number }>]> = [
    ['users', UserModel.deleteMany({})],
    ['memberships', MembershipModel.deleteMany({})],
    ['occupancy', OccupancyRecordModel.deleteMany({})],
    ['bills', BillModel.deleteMany({})],
    ['payments', PaymentModel.deleteMany({})],
    ['receipts', ReceiptModel.deleteMany({})],
    ['additionalServices', FlatAdditionalServiceModel.deleteMany({})],
    ['principalLedger', PrincipalLedgerModel.deleteMany({})],
    ['interestJobRuns', InterestJobRunModel.deleteMany({})],
    ['sequences', SequenceModel.deleteMany({})],
    ['collections', CollectionModel.deleteMany({})],
    ['collectionCharges', CollectionChargeModel.deleteMany({})],
    ['collectionPayments', CollectionPaymentModel.deleteMany({})],
    ['collectionReceipts', CollectionReceiptModel.deleteMany({})],
    ['collectionAdjustments', CollectionAdjustmentModel.deleteMany({})],
    ['refreshSessions', RefreshSessionModel.deleteMany({})],
    ['otpChallenges', OtpChallengeModel.deleteMany({})],
    ['auditLogs', AuditLogModel.deleteMany({})],
    ['notifications', NotificationModel.deleteMany({})],
    ['deviceTokens', DeviceTokenModel.deleteMany({})],
    ['visitors', VisitorLogModel.deleteMany({})],
    ['parcels', ParcelHandoverModel.deleteMany({})],
    ['vehicles', VehicleModel.deleteMany({})],
    ['vehicleLogs', VehicleLogModel.deleteMany({})],
    ['parkingAllocations', ParkingAllocationModel.deleteMany({})],
    ['parkingSlots', ParkingSlotModel.deleteMany({})],
    ['complaints', ComplaintModel.deleteMany({})],
    ['complaintHistory', ComplaintHistoryModel.deleteMany({})],
    ['announcements', AnnouncementModel.deleteMany({})],
    ['announcementReads', AnnouncementReadModel.deleteMany({})],
    ['staff', StaffModel.deleteMany({})],
    ['staffShifts', StaffShiftModel.deleteMany({})],
    ['staffAttendance', StaffAttendanceModel.deleteMany({})],
    ['facilities', FacilityModel.deleteMany({})],
    ['facilityBookings', FacilityBookingModel.deleteMany({})],
  ];

  const counts: Record<string, number> = {};
  for (const [name, job] of jobs) {
    const result = await job;
    counts[name] = result.deletedCount ?? 0;
  }
  return counts;
}

async function resetFlats(): Promise<number> {
  const result = await FlatModel.updateMany(
    {},
    {
      $set: { occupancyStatus: 'VACANT' },
      $unset: { activeOwnerUserId: 1, activeTenantUserId: 1 },
    },
  );
  return result.modifiedCount;
}

async function provisionAdmins(societyId: string): Promise<void> {
  for (const admin of ADMINS) {
    const username = assertValidUsername(admin.username);
    const email = normalizeEmail(admin.email);
    const passwordHash = await hashPassword(admin.password);
    const user = await UserModel.create({
      email,
      username,
      passwordHash,
      mustChangePassword: admin.mustChangePassword,
      passwordChangedAt: admin.mustChangePassword ? undefined : new Date(),
      name: admin.name,
      roles: ['ADMIN'],
      isActive: true,
      canLogin: true,
      primarySocietyId: societyId,
      failedLoginAttempts: 0,
    });
    await MembershipModel.create({
      societyId,
      userId: user._id,
      role: 'ADMIN',
      flatId: null,
      wingId: null,
      isActive: true,
    });
  }
}

async function main(): Promise<void> {
  if (!process.argv.includes('--confirm')) {
    throw new Error('Refusing to run. Pass --confirm to wipe operational data and recreate launch admins.');
  }

  loadEnv();
  await connectDatabase();

  const society = await SocietyModel.findOne({ code: SOCIETY_CODE });
  if (!society) {
    throw new Error(`Society ${SOCIETY_CODE} not found. Run npm run seed first.`);
  }

  const wiped = await wipeOperationalData();
  const vacated = await resetFlats();
  await provisionAdmins(String(society._id));

  const flats = await FlatModel.find({ societyId: society._id }).lean();
  const wings = await WingModel.countDocuments({ societyId: society._id });
  const users = await UserModel.find({}).select('username email mustChangePassword roles').lean();
  const monthly = flats.reduce((sum, flat) => sum + flat.maintenanceRate, 0);

  process.stdout.write(
    `${JSON.stringify(
      {
        society: society.name,
        wings,
        flats: flats.length,
        vacantFlats: flats.filter((flat) => flat.occupancyStatus === 'VACANT').length,
        monthlyMaintenance: monthly,
        vacatedFlats: vacated,
        deleted: wiped,
        admins: users.map((user) => ({
          username: user.username,
          email: user.email,
          mustChangePassword: user.mustChangePassword,
          roles: user.roles,
        })),
      },
      null,
      2,
    )}\n`,
  );

  await disconnectDatabase();
}

main().catch(async (error: unknown) => {
  console.error(error);
  await disconnectDatabase().catch(() => undefined);
  process.exit(1);
});
