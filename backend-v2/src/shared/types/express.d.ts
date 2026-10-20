import type { Types } from 'mongoose';
import type { Role } from '../../config/constants';

export interface AuthUser {
  id: string;
  email: string;
  roles: Role[];
  societyIds: string[];
}

declare global {
  namespace Express {
    interface Request {
      requestId: string;
      user?: AuthUser;
      societyId?: Types.ObjectId | string;
      rawBody?: string;
    }
  }
}

export {};
