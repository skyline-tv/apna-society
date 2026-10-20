import { z } from 'zod';
import { ROLES } from '../../../config/constants';

export const provisionUserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(1).max(120),
  roles: z.array(z.enum(ROLES)).min(1),
  societyId: z.string().min(1),
  phone: z.string().optional(),
});
