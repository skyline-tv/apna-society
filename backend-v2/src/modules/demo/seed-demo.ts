import {
  DEMO_ACCOUNTS,
  DEMO_SOCIETY_CODE,
  DEMO_SOCIETY_NAME,
  DEMO_VISITOR_OTP,
  assertSafeDemoMongoUri,
  getMongoUri,
  isDemoMode,
} from '../../config/demo';
import { hashToken } from '../../utils/crypto';
import { parseObjectId } from '../../utils/object-id';
import { hashPassword } from '../../utils/password';
import { createAdditionalService } from '../billing/services/additional-service.service';
import { generateBills } from '../billing/services/bill-generation.service';
import { recordOfflinePayment } from '../billing/services/payment.service';
import { createCollection } from '../collections/services/collection.service';
import { assignOwner, assignTenant } from '../society/services/occupancy-lifecycle.service';
import { FlatModel } from '../society/models/flat.model';
import { SocietyModel } from '../society/models/society.model';
import { WingModel } from '../society/models/wing.model';
import { MembershipModel } from '../users/models/membership.model';
import { UserModel } from '../users/models/user.model';
import { adminRegisterVehicle } from '../vehicles/services/vehicle.service';
import { VisitorLogModel } from '../visitors/models/visitor-log.model';

type Actor = { userId: string };

export interface DemoSeedResult {
  societyId: string;
  societyName: string;
  created: boolean;
  accounts: Array<{ role: string; username: string }>;
}

async function upsertDemoUser(input: {
  societyId: string;
  username: string;
  password: string;
  email: string;
  name: string;
  mobileE164: string;
  role: 'ADMIN' | 'OWNER' | 'TENANT' | 'GUARD';
}) {
  const passwordHash = await hashPassword(input.password);
  const existing = await UserModel.findOne({ username: input.username }).select('+passwordHash');
  if (existing) {
    existing.passwordHash = passwordHash;
    existing.mustChangePassword = false;
    existing.isActive = true;
    existing.canLogin = true;
    if (!existing.primarySocietyId) {
      existing.primarySocietyId = parseObjectId(input.societyId, 'societyId');
    }
    existing.mobileE164 = input.mobileE164;
    existing.mobileVerifiedAt = new Date();
    if (!existing.roles.includes(input.role)) existing.roles.push(input.role);
    await existing.save();
    return existing;
  }
  return UserModel.create({
    email: input.email,
    username: input.username,
    passwordHash,
    mustChangePassword: false,
    passwordChangedAt: new Date(),
    name: input.name,
    roles: [input.role],
    isActive: true,
    canLogin: true,
    primarySocietyId: input.societyId,
    mobileE164: input.mobileE164,
    mobileVerifiedAt: new Date(),
    phone: `+${input.mobileE164}`,
  });
}

async function ensureMembership(
  societyId: string,
  userId: string,
  role: 'ADMIN' | 'OWNER' | 'TENANT' | 'GUARD',
  flatId?: string,
) {
  const query = {
    societyId,
    userId,
    role,
    isActive: true,
    ...(flatId ? { flatId } : { flatId: null }),
  };
  const existing = await MembershipModel.findOne(query);
  if (existing) return existing;
  return MembershipModel.create({
    societyId,
    userId,
    role,
    flatId: flatId ?? null,
    isActive: true,
    startsAt: new Date('2026-01-01T00:00:00.000+05:30'),
  });
}

export async function seedDemoDataset(): Promise<DemoSeedResult> {
  if (!isDemoMode()) {
    throw new Error('seedDemoDataset requires DEMO_MODE=true and never runs against production');
  }
  assertSafeDemoMongoUri(getMongoUri());

  let created = false;
  let society = await SocietyModel.findOne({ code: DEMO_SOCIETY_CODE });
  if (!society) {
    society = await SocietyModel.create({
      name: DEMO_SOCIETY_NAME,
      code: DEMO_SOCIETY_CODE,
      address: '12 Fiction Lane, Kalyani Nagar',
      city: 'Pune',
      state: 'Maharashtra',
      pincode: '411014',
      contactEmail: 'office@maplegrove.example.com',
      contactPhone: '+91 90000 00000',
      isActive: true,
      config: {
        currency: 'INR',
        timezone: 'Asia/Kolkata',
        maintenanceDayOfMonth: 1,
        annualInterestRateBps: 2400,
        visitorApprovalPolicy: 'PRIMARY_OCCUPIER',
      },
    });
    created = true;
  }

  const societyId = String(society._id);

  const admin = await upsertDemoUser({ societyId, ...DEMO_ACCOUNTS.admin });
  const owner = await upsertDemoUser({ societyId, ...DEMO_ACCOUNTS.owner });
  const tenant = await upsertDemoUser({ societyId, ...DEMO_ACCOUNTS.tenant });
  const guard = await upsertDemoUser({ societyId, ...DEMO_ACCOUNTS.guard });
  const landlord = await upsertDemoUser({
    societyId,
    username: 'demo_landlord',
    password: DEMO_ACCOUNTS.owner.password,
    email: 'demo.landlord@example.com',
    name: 'Kavita Joshi',
    mobileE164: '919000000005',
    role: 'OWNER',
  });
  const ownerB = await upsertDemoUser({
    societyId,
    username: 'demo_ownerb',
    password: DEMO_ACCOUNTS.owner.password,
    email: 'demo.ownerb@example.com',
    name: 'Vikram Desai',
    mobileE164: '919000000006',
    role: 'OWNER',
  });
  const ownerC = await upsertDemoUser({
    societyId,
    username: 'demo_ownerc',
    password: DEMO_ACCOUNTS.owner.password,
    email: 'demo.ownerc@example.com',
    name: 'Meera Nair',
    mobileE164: '919000000007',
    role: 'OWNER',
  });

  await ensureMembership(societyId, String(admin._id), 'ADMIN');
  await ensureMembership(societyId, String(guard._id), 'GUARD');
  await ensureMembership(societyId, String(owner._id), 'OWNER');
  await ensureMembership(societyId, String(tenant._id), 'TENANT');
  await ensureMembership(societyId, String(landlord._id), 'OWNER');
  await ensureMembership(societyId, String(ownerB._id), 'OWNER');
  await ensureMembership(societyId, String(ownerC._id), 'OWNER');

  const actor: Actor = { userId: String(admin._id) };

  async function ensureWing(code: string, floors: number, sortOrder: number) {
    let wing = await WingModel.findOne({ societyId, code });
    if (!wing) {
      wing = await WingModel.create({
        societyId,
        name: `Wing ${code}`,
        code,
        floors,
        flatsPerFloor: 2,
        sortOrder,
        isActive: true,
      });
    }
    return wing;
  }

  const wingA = await ensureWing('A', 2, 1);
  const wingB = await ensureWing('B', 2, 2);

  const flatSpecs = [
    { wing: wingA, number: 'A-101', floor: 1, position: 1, rate: 4000, type: '2BHK' as const },
    { wing: wingA, number: 'A-102', floor: 1, position: 2, rate: 5000, type: '3BHK' as const },
    { wing: wingA, number: 'A-201', floor: 2, position: 1, rate: 4000, type: '2BHK' as const },
    { wing: wingA, number: 'A-202', floor: 2, position: 2, rate: 4000, type: '2BHK' as const },
    { wing: wingB, number: 'B-101', floor: 1, position: 1, rate: 4000, type: '2BHK' as const },
    { wing: wingB, number: 'B-102', floor: 1, position: 2, rate: 5000, type: '3BHK' as const },
    { wing: wingB, number: 'B-201', floor: 2, position: 1, rate: 4000, type: '2BHK' as const },
    { wing: wingB, number: 'B-202', floor: 2, position: 2, rate: 4000, type: '2BHK' as const },
  ];

  const flats = [];
  for (const spec of flatSpecs) {
    let flat = await FlatModel.findOne({ societyId, number: spec.number });
    if (!flat) {
      flat = await FlatModel.create({
        societyId,
        wingId: spec.wing._id,
        number: spec.number,
        floor: spec.floor,
        position: spec.position,
        flatType: spec.type,
        maintenanceRate: spec.rate,
        isActive: true,
        occupancyStatus: 'VACANT',
      });
    }
    flats.push(flat);
  }

  const byNumber = new Map(flats.map((flat) => [flat.number, flat]));

  async function occupyOwner(number: string, userId: string) {
    const flat = byNumber.get(number)!;
    if (flat.activeOwnerUserId) return;
    await assignOwner(
      societyId,
      String(flat._id),
      { userId, effectiveFrom: '2026-01-01T00:00:00.000+05:30' },
      actor,
    );
    const refreshed = await FlatModel.findById(flat._id);
    if (refreshed) byNumber.set(number, refreshed);
  }

  await occupyOwner('A-101', String(owner._id));
  await occupyOwner('A-102', String(landlord._id));
  await occupyOwner('A-202', String(ownerB._id));
  await occupyOwner('B-102', String(ownerC._id));

  const a102 = byNumber.get('A-102')!;
  if (!a102.activeTenantUserId) {
    await assignTenant(
      societyId,
      String(a102._id),
      { userId: String(tenant._id), effectiveFrom: '2026-02-01T00:00:00.000+05:30' },
      actor,
    );
  }

  await ensureMembership(societyId, String(owner._id), 'OWNER', String(byNumber.get('A-101')!._id));
  await ensureMembership(societyId, String(tenant._id), 'TENANT', String(byNumber.get('A-102')!._id));

  const existingBills = await generateBills(
    societyId,
    { billingPeriodStart: new Date('2026-03-01T00:00:00.000+05:30'), numberOfMonths: 1 },
    actor,
  );
  if (existingBills.createdCount > 0) {
    const ownerMarch = existingBills.created.find(
      (bill) => bill.flatId === String(byNumber.get('A-101')!._id),
    );
    if (ownerMarch) {
      await recordOfflinePayment(
        societyId,
        {
          billId: ownerMarch.id,
          amountPaise: ownerMarch.totalAmountPaise,
          paidAt: new Date('2026-03-08T11:00:00.000+05:30'),
          paymentMethod: 'CASH',
          referenceNumber: 'DEMO-CASH-MAR-A101',
          notes: 'Simulated cash payment',
          idempotencyKey: 'demo-march-a101',
        },
        actor,
      );
    }
  }

  const april = await generateBills(
    societyId,
    {
      billingPeriodStart: new Date('2026-04-01T00:00:00.000+05:30'),
      numberOfMonths: 1,
      dueDate: new Date('2026-04-15T00:00:00.000+05:30'),
    },
    actor,
  );
  if (april.createdCount > 0) {
    const tenantApril = april.created.find(
      (bill) => bill.flatId === String(byNumber.get('A-102')!._id),
    );
    if (tenantApril) {
      await recordOfflinePayment(
        societyId,
        {
          billId: tenantApril.id,
          amountPaise: 200_000,
          paidAt: new Date('2026-04-18T10:00:00.000+05:30'),
          paymentMethod: 'CASH',
          referenceNumber: 'DEMO-PARTIAL-APR-A102',
          notes: 'Simulated partial payment',
          idempotencyKey: 'demo-april-a102-partial',
        },
        actor,
      );
    }
  }

  await generateBills(
    societyId,
    {
      billingPeriodStart: new Date('2026-05-01T00:00:00.000+05:30'),
      numberOfMonths: 1,
      dueDate: new Date('2026-05-20T00:00:00.000+05:30'),
    },
    actor,
  );

  try {
    await createAdditionalService(
      societyId,
      {
        flatId: String(byNumber.get('A-101')!._id),
        name: 'Covered car parking',
        description: 'Sample additional service',
        monthlyChargePaise: 50_000,
        quantity: 1,
        effectiveFrom: new Date('2026-03-01T00:00:00.000+05:30'),
      },
      actor,
    );
  } catch {
    // Idempotent re-seed may hit the active-slot unique constraint.
  }

  try {
    await createCollection(
      societyId,
      {
        title: 'Festival lighting 2026',
        description: 'Sample one-time collection for common-area lighting.',
        amountMode: 'PER_FLAT',
        assignmentType: 'SELECTED_FLATS',
        amountPaise: 150_000,
        flatIds: [String(byNumber.get('A-101')!._id), String(byNumber.get('A-102')!._id)],
        dueDate: new Date('2026-06-30T00:00:00.000+05:30'),
        paymentInstructions: 'Simulated collection — no real money is collected.',
        allowPartialPayment: true,
      },
      actor,
    );
  } catch {
    // Already created on re-seed.
  }

  try {
    await adminRegisterVehicle(
      societyId,
      {
        flatId: String(byNumber.get('A-101')!._id),
        registeredUserId: String(owner._id),
        vehicleType: 'FOUR_WHEELER',
        registrationNumber: 'MH12DE0001',
        make: 'Sample',
        model: 'Hatchback',
        colour: 'Silver',
        parkingNumber: 'P-12',
      },
      actor,
    );
  } catch {
    // Already registered.
  }

  const visitorCount = await VisitorLogModel.countDocuments({ societyId });
  if (visitorCount === 0) {
    const otpHash = hashToken(DEMO_VISITOR_OTP);
    await VisitorLogModel.create([
      {
        societyId,
        flatId: byNumber.get('A-101')!._id,
        wingId: wingA._id,
        visitorName: 'Neha Kapoor',
        visitorPhone: '919000000111',
        visitorEmail: 'neha.visitor@example.com',
        visitorType: 'GUEST',
        purpose: 'Family visit',
        numberOfVisitors: 1,
        requestedByGuardId: guard._id,
        assignedResidentUserId: owner._id,
        assignedResidentRole: 'OWNER',
        notifiedResidentUserIds: [owner._id],
        approvalStatus: 'APPROVED',
        entryStatus: 'NOT_ENTERED',
        entryMode: 'OTP',
        entryOtpHash: otpHash,
        entryOtpExpiresAt: new Date('2099-12-31T23:59:59.999Z'),
        otpAttempts: 0,
        approvedAt: new Date(),
        flatNumberSnapshot: 'A-101',
        wingCodeSnapshot: 'A',
      },
      {
        societyId,
        flatId: byNumber.get('A-101')!._id,
        wingId: wingA._id,
        visitorName: 'Courier Demo',
        visitorPhone: '919000000112',
        visitorType: 'COURIER',
        purpose: 'Package delivery',
        numberOfVisitors: 1,
        requestedByGuardId: guard._id,
        assignedResidentUserId: owner._id,
        assignedResidentRole: 'OWNER',
        notifiedResidentUserIds: [owner._id],
        approvalStatus: 'APPROVED',
        entryStatus: 'EXITED',
        entryMode: 'OTP',
        resolution: 'ENTRY',
        entryOtpHash: otpHash,
        entryOtpExpiresAt: new Date('2099-12-31T23:59:59.999Z'),
        otpAttempts: 0,
        otpVerifiedAt: new Date('2026-04-02T10:00:00.000+05:30'),
        approvedAt: new Date('2026-04-02T09:50:00.000+05:30'),
        entryAt: new Date('2026-04-02T10:05:00.000+05:30'),
        exitAt: new Date('2026-04-02T10:20:00.000+05:30'),
        checkedInBy: guard._id,
        checkedOutBy: guard._id,
        flatNumberSnapshot: 'A-101',
        wingCodeSnapshot: 'A',
      },
    ]);
  }

  return {
    societyId,
    societyName: society.name,
    created,
    accounts: [
      { role: 'ADMIN', username: DEMO_ACCOUNTS.admin.username },
      { role: 'OWNER', username: DEMO_ACCOUNTS.owner.username },
      { role: 'TENANT', username: DEMO_ACCOUNTS.tenant.username },
      { role: 'GUARD', username: DEMO_ACCOUNTS.guard.username },
    ],
  };
}
