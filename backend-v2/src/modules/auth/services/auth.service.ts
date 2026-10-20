import { randomUUID } from 'crypto';
import {
  OTP_LENGTH,
  OTP_MAX_ATTEMPTS,
  OTP_MAX_REQUESTS_PER_WINDOW,
  OTP_REQUEST_WINDOW_MS,
  OTP_RESEND_COOLDOWN_MS,
  OTP_TTL_MS,
} from '../../../config/constants';
import { getEnv } from '../../../config/env';
import {
  forbidden,
  tooManyRequests,
  unauthorized,
} from '../../../shared/errors/app-error';
import { generateOtp, generateSecureToken, hashToken, normalizeEmail, safeEqualHex } from '../../../utils/crypto';
import { getLogger } from '../../../utils/logger';
import { MembershipModel } from '../../users/models/membership.model';
import { UserModel } from '../../users/models/user.model';
import { OtpChallengeModel } from '../models/otp-challenge.model';
import { RefreshSessionModel } from '../models/refresh-session.model';
import type { AuthProfile, RequestMeta, TokenPair } from '../types/auth.types';
import { writeAuditLog } from './audit.service';
import { getEmailService } from './email.service';
import { buildTokenPair, parseDurationToMs } from './token.service';

const GENERIC_OTP_MESSAGE =
  'If an account exists for this email, a one-time code has been sent.';

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

export async function requestOtp(emailRaw: string, meta: RequestMeta = {}): Promise<{ message: string }> {
  const email = normalizeEmail(emailRaw);
  const logger = getLogger();
  const now = new Date();

  const user = await UserModel.findOne({ email }).lean();

  // Prevent email enumeration: always return the same message.
  if (!user || !user.isActive || !user.canLogin) {
    logger.info({ emailPresent: Boolean(user) }, 'OTP request for non-loginable account');
    return { message: GENERIC_OTP_MESSAGE };
  }

  const existing = await OtpChallengeModel.findOne({
    email,
    consumedAt: { $exists: false },
    expiresAt: { $gt: now },
  })
    .sort({ createdAt: -1 })
    .select('+otpHash');

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

  const otp = generateOtp(OTP_LENGTH);
  const otpHash = hashToken(otp);
  const expiresAt = new Date(now.getTime() + OTP_TTL_MS);

  if (existing) {
    const windowAge = now.getTime() - existing.requestWindowStartedAt.getTime();
    const resetWindow = windowAge > OTP_REQUEST_WINDOW_MS;
    existing.otpHash = otpHash;
    existing.expiresAt = expiresAt;
    existing.attemptCount = 0;
    existing.maxAttempts = OTP_MAX_ATTEMPTS;
    existing.lastSentAt = now;
    existing.requestCount = resetWindow ? 1 : existing.requestCount + 1;
    existing.requestWindowStartedAt = resetWindow ? now : existing.requestWindowStartedAt;
    existing.ipAddress = meta.ipAddress;
    existing.userAgent = meta.userAgent;
    await existing.save();
  } else {
    await OtpChallengeModel.create({
      email,
      userId: user._id,
      otpHash,
      expiresAt,
      attemptCount: 0,
      maxAttempts: OTP_MAX_ATTEMPTS,
      lastSentAt: now,
      requestCount: 1,
      requestWindowStartedAt: now,
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });
  }

  await getEmailService().sendOtpEmail(email, otp);

  await writeAuditLog({
    action: 'AUTH_OTP_REQUESTED',
    actorUserId: user._id,
    societyId: user.primarySocietyId,
    targetType: 'User',
    targetId: String(user._id),
    metadata: { email },
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });

  return { message: GENERIC_OTP_MESSAGE };
}

export async function verifyOtp(
  emailRaw: string,
  otp: string,
  meta: RequestMeta = {},
): Promise<TokenPair> {
  const email = normalizeEmail(emailRaw);
  const now = new Date();

  const challenge = await OtpChallengeModel.findOne({
    email,
    consumedAt: { $exists: false },
  })
    .sort({ createdAt: -1 })
    .select('+otpHash');

  if (!challenge || challenge.expiresAt.getTime() <= now.getTime()) {
    await writeAuditLog({
      action: 'AUTH_OTP_FAILED',
      metadata: { email, reason: 'expired_or_missing' },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });
    throw unauthorized('Invalid or expired code', 'INVALID_OTP');
  }

  if (challenge.attemptCount >= challenge.maxAttempts) {
    throw tooManyRequests('Too many invalid attempts. Request a new code.', 'OTP_ATTEMPTS_EXCEEDED');
  }

  const candidateHash = hashToken(otp.trim());
  const matches = safeEqualHex(candidateHash, challenge.otpHash);

  if (!matches) {
    challenge.attemptCount += 1;
    await challenge.save();
    await writeAuditLog({
      action: 'AUTH_OTP_FAILED',
      actorUserId: challenge.userId,
      metadata: { email, attempts: challenge.attemptCount },
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });
    if (challenge.attemptCount >= challenge.maxAttempts) {
      throw tooManyRequests('Too many invalid attempts. Request a new code.', 'OTP_ATTEMPTS_EXCEEDED');
    }
    throw unauthorized('Invalid or expired code', 'INVALID_OTP');
  }

  challenge.consumedAt = now;
  await challenge.save();

  const user = await UserModel.findById(challenge.userId);
  if (!user || !user.isActive || !user.canLogin) {
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
