import { afterAll, beforeAll, beforeEach } from 'vitest';
import { MongoMemoryReplSet } from 'mongodb-memory-server';
import mongoose from 'mongoose';
import { loadEnv, resetEnvCache } from '../../src/config/env';
import { connectDatabase, disconnectDatabase } from '../../src/database/connection';
import { resetLogger } from '../../src/utils/logger';
import { resetEmailService, setEmailService } from '../../src/modules/auth/services/email.service';

process.env.NODE_ENV = 'test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret-which-is-long-enough-32';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-which-is-long-enough-32';
process.env.ACCESS_TOKEN_EXPIRY = '15m';
process.env.REFRESH_TOKEN_EXPIRY = '7d';
process.env.CORS_ORIGINS = 'http://localhost:3000';
process.env.EMAIL_FROM = 'test@example.com';
process.env.RESEND_API_KEY = '';
process.env.LOG_LEVEL = 'silent';
process.env.PORT = '4000';
process.env.COMPLAINT_STORAGE_PROVIDER = 'memory';
process.env.FACILITY_PENDING_BOOKING_TTL_MS = '3600000';
process.env.ANNOUNCEMENT_STORAGE_PROVIDER = 'memory';
process.env.ANNOUNCEMENT_WORKER_ENABLED = 'false';
process.env.INTEREST_WORKER_ENABLED = 'false';
process.env.OVERDUE_REMINDER_WORKER_ENABLED = 'false';
process.env.PUSH_RETRY_WORKER_ENABLED = 'false';
process.env.FCM_ENABLED = 'false';
process.env.SMS_PROVIDER = 'memory';
process.env.SMS_OTP_ENABLED = 'false';
process.env.SMS_OTP_DEV_BYPASS = 'false';
process.env.SMS_OTP_LENGTH = '6';
process.env.SMS_OTP_EXPIRY_MINUTES = '5';
// Placeholder until memory server starts; connectDatabase is called in beforeAll with real URI.
process.env.MONGODB_URI = process.env.MONGODB_URI ?? 'mongodb://127.0.0.1:27017/apna_society_test';

resetEnvCache();
resetLogger();
loadEnv();

let replSet: MongoMemoryReplSet | undefined;

/** Legacy email OTP inbox (visitor email OTP / notifications tests). */
export const testOtpInbox: { email: string; otp: string }[] = [];

beforeAll(async () => {
  replSet = await MongoMemoryReplSet.create({
    replSet: { count: 1, storageEngine: 'wiredTiger' },
  });
  const uri = replSet.getUri('apna_society_test');
  process.env.MONGODB_URI = uri;
  resetEnvCache();
  resetLogger();
  loadEnv();
  await connectDatabase(uri);

  // Ensure schema index definitions (including partial unique membership/occupancy indexes) are applied.
  const { MembershipModel } = await import('../../src/modules/users/models/membership.model');
  const { OccupancyRecordModel } = await import(
    '../../src/modules/society/models/occupancy-record.model'
  );
  const { UserModel } = await import('../../src/modules/users/models/user.model');
  const { FlatModel } = await import('../../src/modules/society/models/flat.model');
  const { BillModel } = await import('../../src/modules/billing/models/bill.model');
  const { PaymentModel } = await import('../../src/modules/billing/models/payment.model');
  const { ReceiptModel } = await import('../../src/modules/billing/models/receipt.model');
  const { PrincipalLedgerModel } = await import(
    '../../src/modules/billing/models/principal-ledger.model'
  );
  const { VisitorLogModel } = await import(
    '../../src/modules/visitors/models/visitor-log.model'
  );
  const { VehicleModel } = await import('../../src/modules/vehicles/models/vehicle.model');
  const { ParkingSlotModel } = await import(
    '../../src/modules/vehicles/models/parking-slot.model'
  );
  const { ParkingAllocationModel } = await import(
    '../../src/modules/vehicles/models/parking-allocation.model'
  );
  const { VehicleLogModel } = await import(
    '../../src/modules/vehicles/models/vehicle-log.model'
  );
  const { ComplaintModel } = await import(
    '../../src/modules/complaints/models/complaint.model'
  );
  const { ComplaintHistoryModel } = await import(
    '../../src/modules/complaints/models/complaint-history.model'
  );
  const { StaffModel } = await import('../../src/modules/staff/models/staff.model');
  const { StaffAttendanceModel } = await import(
    '../../src/modules/staff/models/staff-attendance.model'
  );
  const { StaffShiftModel } = await import('../../src/modules/staff/models/staff-shift.model');
  const { FacilityModel } = await import('../../src/modules/facilities/models/facility.model');
  const { FacilityBookingModel } = await import(
    '../../src/modules/facilities/models/facility-booking.model'
  );
  const { AnnouncementModel } = await import(
    '../../src/modules/announcements/models/announcement.model'
  );
  const { AnnouncementReadModel } = await import(
    '../../src/modules/announcements/models/announcement-read.model'
  );
  const { NotificationModel } = await import(
    '../../src/modules/notifications/models/notification.model'
  );
  const { InterestJobRunModel } = await import(
    '../../src/modules/billing/models/interest-job-run.model'
  );
  const { DeviceTokenModel } = await import(
    '../../src/modules/notifications/models/device-token.model'
  );
  const { ParcelHandoverModel } = await import(
    '../../src/modules/visitors/models/parcel-handover.model'
  );
  const { CollectionModel } = await import(
    '../../src/modules/collections/models/collection.model'
  );
  const { CollectionChargeModel } = await import(
    '../../src/modules/collections/models/collection-charge.model'
  );
  const { CollectionPaymentModel } = await import(
    '../../src/modules/collections/models/collection-payment.model'
  );
  const { CollectionReceiptModel } = await import(
    '../../src/modules/collections/models/collection-receipt.model'
  );
  const { CollectionAdjustmentModel } = await import(
    '../../src/modules/collections/models/collection-adjustment.model'
  );
  await Promise.all([
    MembershipModel.syncIndexes(),
    OccupancyRecordModel.syncIndexes(),
    UserModel.syncIndexes(),
    FlatModel.syncIndexes(),
    BillModel.syncIndexes(),
    PaymentModel.syncIndexes(),
    ReceiptModel.syncIndexes(),
    PrincipalLedgerModel.syncIndexes(),
    VisitorLogModel.syncIndexes(),
    VehicleModel.syncIndexes(),
    ParkingSlotModel.syncIndexes(),
    ParkingAllocationModel.syncIndexes(),
    VehicleLogModel.syncIndexes(),
    ComplaintModel.syncIndexes(),
    ComplaintHistoryModel.syncIndexes(),
    StaffModel.syncIndexes(),
    StaffAttendanceModel.syncIndexes(),
    StaffShiftModel.syncIndexes(),
    FacilityModel.syncIndexes(),
    FacilityBookingModel.syncIndexes(),
    AnnouncementModel.syncIndexes(),
    AnnouncementReadModel.syncIndexes(),
    NotificationModel.syncIndexes(),
    InterestJobRunModel.syncIndexes(),
    DeviceTokenModel.syncIndexes(),
    ParcelHandoverModel.syncIndexes(),
    CollectionModel.syncIndexes(),
    CollectionChargeModel.syncIndexes(),
    CollectionPaymentModel.syncIndexes(),
    CollectionReceiptModel.syncIndexes(),
    CollectionAdjustmentModel.syncIndexes(),
  ]);

  setEmailService({
    async sendOtpEmail(to, otp) {
      testOtpInbox.push({ email: to, otp });
    },
    async sendVisitorEntryOtpEmail() {
      // Visitor OTP captured via testVisitorOtpInbox in deliverVisitorEntryOtp.
    },
  });
}, 120_000);

beforeEach(async () => {
  testOtpInbox.length = 0;
  const { clearTestVisitorOtpInbox } = await import(
    '../../src/modules/visitors/providers/visitor-otp-email.provider'
  );
  clearTestVisitorOtpInbox();
  const { getMemoryComplaintStorage } = await import(
    '../../src/modules/complaints/storage/complaint-storage'
  );
  getMemoryComplaintStorage().clear();
  const { getMemoryAnnouncementStorage } = await import(
    '../../src/modules/announcements/storage/announcement-storage'
  );
  getMemoryAnnouncementStorage().clear();
  const { getMemorySmsProvider } = await import(
    '../../src/modules/auth/providers/memory-sms.provider'
  );
  getMemorySmsProvider().clear();
  const { resetPushSenderForTests } = await import(
    '../../src/modules/notifications/services/push-sender'
  );
  resetPushSenderForTests();
  const collections = mongoose.connection.collections;
  await Promise.all(Object.values(collections).map((collection) => collection.deleteMany({})));
});

afterAll(async () => {
  resetEmailService();
  await disconnectDatabase();
  if (replSet) {
    await replSet.stop();
  }
});
