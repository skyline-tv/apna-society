import { randomUUID } from 'crypto';
import {
  OTP_MAX_ATTEMPTS,
  OTP_MAX_REQUESTS_PER_WINDOW,
  OTP_REQUEST_WINDOW_MS,
  OTP_RESEND_COOLDOWN_MS,
} from '../../../config/constants';
import { getEnv } from '../../../config/env';
import {
  badRequest,
  forbidden,
  tooManyRequests,
  unauthorized,
} from '../../../shared/errors/app-error';
import { generateSecureToken, hashToken } from '../../../utils/crypto';
import { normalizeMobileE164 } from '../../../utils/phone';
import { getLogger } from '../../../utils/logger';
import { MembershipModel } from '../../users/models/membership.model';
import { UserModel } from '../../users/models/user.model';
import { OtpChallengeModel } from '../models/otp-challenge.model';
import { RefreshSessionModel } from '../models/refresh-session.model';
import { getSmsProvider } from '../providers/sms-provider.factory';
import type { AuthProfile, RequestMeta, TokenPair } from '../types/auth.types';
import { writeAuditLog } from './audit.service';
import { buildTokenPair, parseDurationToMs } from './token.service';

const GENERIC_OTP_MESSAGE =
  'If an account exists for this mobile number, a one-time code has been sent.';

async function getSocietyIdsForUser(userId: string): Promise<string[]> {
  const memberships = await MembershipModel.find({
    userId,
    isActive: true,
  })
    .select('societyId')
    .lean();
  const fromMemberships = memberships.map((m) => String(m.societyId));
  const user = await UserModel.findById(userId).select('primarySocietyId roles').lean();
  if (user?.primarySocietyId) {
    fromMemberships.push(String(user.primarySocietyId));
  }
  return [...new Set(fromMemberships)];
}

export async function requestOtp(
  mobileRaw: string,
  meta: RequestMeta = {},
): Promise<{ message: string; debugOtp?: string }> {
  const logger = getLogger();
  const env = getEnv();
  const now = new Date();

  let mobileE164: string;
  try {
    mobileE164 = normalizeMobileE164(mobileRaw);
  } catch {
    // Same generic message — do not reveal validation details to enumerators.
    return { message: GENERIC_OTP_MESSAGE };
  }

  const user = await UserModel.findOne({ mobileE164 }).lean();

  // Prevent mobile enumeration: always return the same message.
  if (!user || !user.isActive || !user.canLogin || !user.mobileVerifiedAt) {
    logger.info(
      {
        mobilePresent: Boolean(user),
        verified: Boolean(user?.mobileVerifiedAt),
      },
      'OTP request for non-loginable mobile',
    );
    return { message: GENERIC_OTP_MESSAGE };
  }

  const existing = await OtpChallengeModel.findOne({
    mobileE164,
    consumedAt: { $exists: false },
    expiresAt: { $gt: now },
  })
    .sort({ createdAt: -1 })
    .select('lastSentAt requestCount requestWindowStartedAt');

  if (existing) {
    const sinceLastSend = now.getTime() - existing.lastSentAt.getTime();
    if (sinceLastSend < OTP_RESEND_COOLDOWN_MS) {
      throw tooManyRequests('Please wait before requesting another code', 'OTP_COOLDOWN');
    }

    const windowAge = now.getTime() - existing.requestWindowStartedAt.getTime();
    if (windowAge <= OTP_REQUEST_WINDOW_MS && existing.requestCount >= OTP_MAX_REQUESTS_PER_WINDOW) {
      throw tooManyRequests('Too many OTP requests. Try again later.', 'OTP_RATE_LIMIT');
    }
  }

  const expiryMinutes = env.SMS_OTP_EXPIRY_MINUTES;
  const otpLength = env.SMS_OTP_LENGTH;
  const expiresAt = new Date(now.getTime() + expiryMinutes * 60_000);

  let requestCount = 1;
  let requestWindowStartedAt = now;
  if (existing) {
    const windowAge = now.getTime() - existing.requestWindowStartedAt.getTime();
    const resetWindow = windowAge > OTP_REQUEST_WINDOW_MS;
    requestCount = resetWindow ? 1 : existing.requestCount + 1;
    requestWindowStartedAt = resetWindow ? now : existing.requestWindowStartedAt;
  }

  await OtpChallengeModel.deleteMany({ mobileE164, consumedAt: { $exists: false } });

  const sms = getSmsProvider();
  let providerRequestId: string | undefined;
  let debugOtp: string | undefined;
  try {
    const sent = await sms.sendOtp({
      mobileE164,
      otpLength,
      expiryMinutes,
      userIp: meta.ipAddress,
    });
    providerRequestId = sent.requestId;
    // Dev helpers only — never returned for MSG91 / production.
    if (env.SMS_OTP_DEV_BYPASS && env.NODE_ENV !== 'production' && sent.debugOtp) {
      debugOtp = sent.debugOtp;
    } else if (env.NODE_ENV === 'development' && sms.name === 'memory' && sent.debugOtp) {
      debugOtp = sent.debugOtp;
    }
  } catch (error) {
    logger.error({ err: error, provider: sms.name }, 'SMS OTP send failed');
    throw error;
  }

  await OtpChallengeModel.create({
    mobileE164,
    userId: user._id,
    providerRequestId,
    expiresAt,
    attemptCount: 0,
    maxAttempts: OTP_MAX_ATTEMPTS,
    lastSentAt: now,
    requestCount,
    requestWindowStartedAt,
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });

  await writeAuditLog({
    action: 'AUTH_OTP_REQUESTED',
    actorUserId: user._id,
    societyId: user.primarySocietyId,
    targetType: 'User',
    targetId: String(user._id),
    metadata: { mobileSuffix: mobileE164.slice(-4), provider: sms.name },
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });

  return { message: GENERIC_OTP_MESSAGE, ...(debugOtp ? { debugOtp } : {}) };
}

export async function verifyOtp(
  mobileRaw: string,
  otp: string,
  meta: RequestMeta = {},
): Promise<TokenPair> {
  const now = new Date();
  const mobileE164 = normalizeMobileE164(mobileRaw);
  const normalizedOtp = otp.normalize('NFKC').replace(/\D/g, '');
  const env = getEnv();
  if (!new RegExp(`^\\d{${env.SMS_OTP_LENGTH}}$`).test(normalizedOtp)) {
    throw unauthorized('Invalid or expired code', 'INVALID_OTP');
  }

  const challenge = await OtpChallengeModel.findOne({
    mobileE164,
    consumedAt: { $exists: false },
  }).sort({ createdAt: -1 });

  if (!challenge || challenge.expiresAt.getTime() <= now.getTime()) {
    await writeAuditLog({
      action: 'AUTH_OTP_FAILED',
      metadata: { mobileSuffix: mobileE164.slice(-4), reason: 'expired_or_missing' },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });
    throw unauthorized('Invalid or expired code', 'INVALID_OTP');
  }

  if (challenge.attemptCount >= challenge.maxAttempts) {
    throw tooManyRequests('Too many invalid attempts. Request a new code.', 'OTP_ATTEMPTS_EXCEEDED');
  }

  const sms = getSmsProvider();
  const verified = await sms.verifyOtp({ mobileE164, otp: normalizedOtp });

  if (!verified.verified) {
    challenge.attemptCount += 1;
    await challenge.save();
    await writeAuditLog({
      action: 'AUTH_OTP_FAILED',
      actorUserId: challenge.userId,
      metadata: {
        mobileSuffix: mobileE164.slice(-4),
        attempts: challenge.attemptCount,
        reason: verified.reason ?? 'INVALID',
      },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });
    if (challenge.attemptCount >= challenge.maxAttempts) {
      throw tooManyRequests('Too many invalid attempts. Request a new code.', 'OTP_ATTEMPTS_EXCEEDED');
    }
    if (verified.reason === 'PROVIDER_ERROR') {
      throw badRequest('Unable to verify OTP right now. Try again later.', 'SMS_VERIFY_FAILED');
    }
    throw unauthorized('Invalid or expired code', 'INVALID_OTP');
  }

  challenge.consumedAt = now;
  await challenge.save();

  const user = await UserModel.findById(challenge.userId);
  if (
    !user ||
    !user.isActive ||
    !user.canLogin ||
    !user.mobileVerifiedAt ||
    user.mobileE164 !== mobileE164
  ) {
    throw unauthorized('Account is not allowed to log in', 'LOGIN_DISABLED');
  }

  user.lastLoginAt = now;
  await user.save();

  const tokens = await issueTokenPair(String(user._id), meta);

  await writeAuditLog({
    action: 'AUTH_OTP_VERIFIED',
    actorUserId: user._id,
    societyId: user.primarySocietyId,
    targetType: 'User',
    targetId: String(user._id),
    metadata: { mobileSuffix: mobileE164.slice(-4), provider: sms.name },
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });

  return tokens;
}

async function issueTokenPair(userId: string, meta: RequestMeta, familyId?: string): Promise<TokenPair> {
  const user = await UserModel.findById(userId).lean();
  if (!user) {
    throw unauthorized('User not found', 'USER_NOT_FOUND');
  }

  const societyIds = await getSocietyIdsForUser(userId);
  const refreshToken = generateSecureToken(48);
  const tokenHash = hashToken(refreshToken);
  const env = getEnv();
  const expiresAt = new Date(Date.now() + parseDurationToMs(env.REFRESH_TOKEN_EXPIRY));

  await RefreshSessionModel.create({
    userId,
    tokenHash,
    familyId: familyId ?? randomUUID(),
    expiresAt,
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });

  return buildTokenPair({
    userId,
    email: user.email,
    roles: user.roles,
    societyIds,
    refreshToken,
  });
}

export async function refreshTokens(refreshToken: string, meta: RequestMeta = {}): Promise<TokenPair> {
  if (!refreshToken) {
    throw unauthorized('Refresh token required', 'REFRESH_REQUIRED');
  }

  const tokenHash = hashToken(refreshToken);
  const session = await RefreshSessionModel.findOne({ tokenHash }).select('+tokenHash');

  if (!session) {
    throw unauthorized('Invalid refresh token', 'INVALID_REFRESH');
  }

  if (session.revokedAt || session.reuseDetectedAt) {
    await RefreshSessionModel.updateMany(
      { familyId: session.familyId, revokedAt: { $exists: false } },
      { $set: { revokedAt: new Date(), reuseDetectedAt: new Date() } },
    );
    await writeAuditLog({
      action: 'AUTH_REFRESH_REUSE',
      actorUserId: session.userId,
      metadata: { familyId: session.familyId },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });
    throw unauthorized('Refresh token reuse detected. Please sign in again.', 'REFRESH_REUSE');
  }

  if (session.expiresAt.getTime() <= Date.now()) {
    throw unauthorized('Refresh token expired', 'REFRESH_EXPIRED');
  }

  const user = await UserModel.findById(session.userId);
  if (!user || !user.isActive || !user.canLogin) {
    throw unauthorized('Account is not allowed to log in', 'LOGIN_DISABLED');
  }

  const newRefreshToken = generateSecureToken(48);
  const newHash = hashToken(newRefreshToken);
  const env = getEnv();
  const expiresAt = new Date(Date.now() + parseDurationToMs(env.REFRESH_TOKEN_EXPIRY));

  session.revokedAt = new Date();
  session.replacedByHash = newHash;
  await session.save();

  await RefreshSessionModel.create({
    userId: user._id,
    tokenHash: newHash,
    familyId: session.familyId,
    expiresAt,
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });

  const societyIds = await getSocietyIdsForUser(String(user._id));

  await writeAuditLog({
    action: 'AUTH_REFRESH',
    actorUserId: user._id,
    societyId: user.primarySocietyId,
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });

  return buildTokenPair({
    userId: String(user._id),
    email: user.email,
    roles: user.roles,
    societyIds,
    refreshToken: newRefreshToken,
  });
}

export async function logout(refreshToken: string | undefined, meta: RequestMeta = {}): Promise<void> {
  if (!refreshToken) {
    return;
  }
  const tokenHash = hashToken(refreshToken);
  const session = await RefreshSessionModel.findOne({ tokenHash }).select('+tokenHash');
  if (!session || session.revokedAt) {
    return;
  }
  session.revokedAt = new Date();
  await session.save();
  await writeAuditLog({
    action: 'AUTH_LOGOUT',
    actorUserId: session.userId,
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });
}

export async function logoutAll(userId: string, meta: RequestMeta = {}): Promise<{ revoked: number }> {
  const result = await RefreshSessionModel.updateMany(
    { userId, revokedAt: { $exists: false } },
    { $set: { revokedAt: new Date() } },
  );
  await writeAuditLog({
    action: 'AUTH_LOGOUT_ALL',
    actorUserId: userId,
    metadata: { revoked: result.modifiedCount },
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });
  return { revoked: result.modifiedCount };
}

export async function getProfile(userId: string): Promise<AuthProfile> {
  const user = await UserModel.findById(userId).lean();
  if (!user) {
    throw unauthorized('User not found', 'USER_NOT_FOUND');
  }
  const societyIds = await getSocietyIdsForUser(userId);
  return {
    id: String(user._id),
    email: user.email,
    name: user.name,
    phone: user.phone,
    mobileE164: user.mobileE164,
    mobileVerified: Boolean(user.mobileVerifiedAt),
    roles: user.roles,
    societyIds,
    primarySocietyId: user.primarySocietyId ? String(user.primarySocietyId) : undefined,
    lastLoginAt: user.lastLoginAt?.toISOString(),
  };
}

export function assertSocietyAccess(userSocietyIds: string[], societyId: string): void {
  if (!userSocietyIds.includes(societyId)) {
    throw forbidden('Society access denied', 'SOCIETY_ISOLATION');
  }
}
