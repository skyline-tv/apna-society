import jwt from 'jsonwebtoken';
import { getEnv } from '../../../config/env';
import { unauthorized } from '../../../shared/errors/app-error';
import type { AccessTokenPayload, TokenPair } from '../types/auth.types';
import type { Role } from '../../../config/constants';

export function signAccessToken(payload: Omit<AccessTokenPayload, 'type'>): string {
  const env = getEnv();
  return jwt.sign({ ...payload, type: 'access' satisfies AccessTokenPayload['type'] }, env.JWT_ACCESS_SECRET, {
    expiresIn: env.ACCESS_TOKEN_EXPIRY as jwt.SignOptions['expiresIn'],
  });
}

export function verifyAccessToken(token: string): AccessTokenPayload {
  const env = getEnv();
  try {
    const payload = jwt.verify(token, env.JWT_ACCESS_SECRET) as AccessTokenPayload;
    if (payload.type !== 'access') {
      throw unauthorized('Invalid access token', 'INVALID_TOKEN');
    }
    return payload;
  } catch {
    throw unauthorized('Invalid or expired access token', 'INVALID_TOKEN');
  }
}

export function buildTokenPair(input: {
  userId: string;
  email: string;
  roles: Role[];
  societyIds: string[];
  refreshToken: string;
  mustChangePassword?: boolean;
}): TokenPair {
  const env = getEnv();
  return {
    accessToken: signAccessToken({
      sub: input.userId,
      email: input.email,
      roles: input.roles,
      societyIds: input.societyIds,
    }),
    refreshToken: input.refreshToken,
    expiresIn: env.ACCESS_TOKEN_EXPIRY,
    tokenType: 'Bearer',
    mustChangePassword: Boolean(input.mustChangePassword),
  };
}

export function parseDurationToMs(duration: string): number {
  const match = /^(\d+)([smhd])$/.exec(duration.trim());
  if (!match) {
    throw new Error(`Unsupported duration format: ${duration}`);
  }
  const value = Number(match[1]);
  const unit = match[2];
  const multipliers: Record<string, number> = {
    s: 1000,
    m: 60_000,
    h: 3_600_000,
    d: 86_400_000,
  };
  return value * multipliers[unit];
}
