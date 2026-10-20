/**
 * Admin provisioning helper (no public registration).
 *
 * Usage:
 *   npm run prepare:admin -- --email admin@example.com --name "Society Admin" --mobile 9876543210
 *
 * Mobile is optional. When provided it is stored as verified so SMS OTP login works.
 */
import { loadEnv } from '../src/config/env';
import { connectDatabase, disconnectDatabase } from '../src/database/connection';
import { UserModel } from '../src/modules/users/models/user.model';
import { SocietyModel } from '../src/modules/society/models/society.model';
import { MembershipModel } from '../src/modules/users/models/membership.model';
import { normalizeEmail } from '../src/utils/crypto';
import { normalizeMobileE164 } from '../src/utils/phone';
import { writeAuditLog } from '../src/modules/auth/services/audit.service';

function arg(name: string): string | undefined {
  const idx = process.argv.indexOf(`--${name}`);
  if (idx === -1) return undefined;
  return process.argv[idx + 1];
}

async function main(): Promise<void> {
  loadEnv();
  const email = normalizeEmail(arg('email') ?? '');
  const name = (arg('name') ?? 'Platform Admin').trim();
  const societyCode = (arg('society') ?? 'MONARCH_SOLITAIRE').toUpperCase();
  const mobileRaw = arg('mobile');

  if (!email || !email.includes('@')) {
    throw new Error('Provide --email');
  }

  await connectDatabase();

  const society = await SocietyModel.findOne({ code: societyCode });
  if (!society) {
    throw new Error(`Society ${societyCode} not found. Run npm run seed first.`);
  }

  let mobileE164: string | undefined;
  if (mobileRaw) {
    mobileE164 = normalizeMobileE164(mobileRaw);
  }

  let user = await UserModel.findOne({ email });
  if (!user) {
    user = await UserModel.create({
      email,
      name,
      roles: ['ADMIN'],
      isActive: true,
      canLogin: true,
      primarySocietyId: society._id,
      ...(mobileE164
        ? {
            mobileE164,
            mobileVerifiedAt: new Date(),
            phone: `+${mobileE164}`,
          }
        : {}),
    });
  } else {
    if (!user.roles.includes('ADMIN')) {
      user.roles = [...new Set([...user.roles, 'ADMIN' as const])];
    }
    user.canLogin = true;
    user.isActive = true;
    user.primarySocietyId = user.primarySocietyId ?? society._id;
    if (mobileE164) {
      user.mobileE164 = mobileE164;
      user.mobileVerifiedAt = new Date();
      user.phone = user.phone ?? `+${mobileE164}`;
    }
    await user.save();
  }

  const membership = await MembershipModel.findOne({
    societyId: society._id,
    userId: user._id,
    role: 'ADMIN',
  });
  if (!membership) {
    await MembershipModel.create({
      societyId: society._id,
      userId: user._id,
      role: 'ADMIN',
      flatId: null,
      wingId: null,
      isActive: true,
    });
  }

  await writeAuditLog({
    action: 'USER_PROVISIONED',
    actorUserId: user._id,
    societyId: society._id,
    targetType: 'User',
    targetId: String(user._id),
    metadata: {
      email,
      role: 'ADMIN',
      mobileSuffix: user.mobileE164?.slice(-4),
      mobileVerified: Boolean(user.mobileVerifiedAt),
    },
  });

  process.stdout.write(
    `${JSON.stringify(
      {
        id: user.id,
        email: user.email,
        mobileE164: user.mobileE164,
        mobileVerified: Boolean(user.mobileVerifiedAt),
        roles: user.roles,
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
