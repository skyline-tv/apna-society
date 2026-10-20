import type { Role } from '../../../config/constants';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresIn: string;
  tokenType: 'Bearer';
  mustChangePassword?: boolean;
}

export interface AccessTokenPayload {
  sub: string;
  email: string;
  roles: Role[];
  societyIds: string[];
  type: 'access';
}

export interface AuthProfile {
  id: string;
  email: string;
  username?: string;
  name: string;
  phone?: string;
  mobileE164?: string;
  mobileVerified: boolean;
  roles: Role[];
  societyIds: string[];
  primarySocietyId?: string;
  lastLoginAt?: string;
  mustChangePassword: boolean;
}

export interface RequestMeta {
  ipAddress?: string;
  userAgent?: string;
}
