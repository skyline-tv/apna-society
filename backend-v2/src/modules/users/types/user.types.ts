import type { Role } from '../../../config/constants';

export interface UserSummary {
  id: string;
  email: string;
  name: string;
  roles: Role[];
  isActive: boolean;
  canLogin: boolean;
  primarySocietyId?: string;
}
