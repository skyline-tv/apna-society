import type { Role } from '../../../config/constants';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresIn: string;
  tokenType: 'Bearer';
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
  name: string;
  phone?: string;
  roles: Role[];
  societyIds: string[];
  primarySocietyId?: string;
  lastLoginAt?: string;
}

export interface RequestMeta {
  ipAddress?: string;
  userAgent?: string;
}
