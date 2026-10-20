import { SocietyModel } from '../../src/modules/society/models/society.model';
import { UserModel } from '../../src/modules/users/models/user.model';
import { MembershipModel } from '../../src/modules/users/models/membership.model';
import type { Role } from '../../src/config/constants';

/** Unique Indian test mobiles (91 + 10 digits starting 6–9). */
let testMobileSeq = 0;
export function nextTestMobileE164(): string {
  testMobileSeq += 1;
  const local = String(7000000000 + testMobileSeq);
  return `91${local}`;
}

export async function createSociety(code = 'TEST_SOC') {
  return SocietyModel.create({
    name: 'Test Society',
    code,
    isActive: true,
  });
}

export async function createUser(input: {
  email: string;
  name?: string;
  roles?: Role[];
  societyId?: string;
  canLogin?: boolean;
  isActive?: boolean;
  mobileE164?: string;
  /** When false, skips assigning a mobile (or leaves it unverified if mobileE164 set). */
  mobileVerified?: boolean;
  /** When true, do not auto-assign a test mobile. */
  skipMobile?: boolean;
}) {
  const mobileE164 =
    input.mobileE164 ?? (input.skipMobile ? undefined : nextTestMobileE164());
  const verified =
    input.mobileVerified === false
      ? undefined
      : mobileE164
        ? new Date()
        : undefined;

  const user = await UserModel.create({
    email: input.email,
    name: input.name ?? 'Test User',
    roles: input.roles ?? ['OWNER'],
    canLogin: input.canLogin ?? true,
    isActive: input.isActive ?? true,
    primarySocietyId: input.societyId,
    mobileE164,
    mobileVerifiedAt: verified,
    phone: mobileE164 ? `+${mobileE164}` : undefined,
  });

  if (input.societyId) {
    await MembershipModel.create({
      societyId: input.societyId,
      userId: user._id,
      role: (input.roles ?? ['OWNER'])[0],
      flatId: null,
      wingId: null,
      isActive: true,
    });
  }

  return user;
}
