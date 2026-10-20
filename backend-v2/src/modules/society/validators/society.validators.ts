import { z } from 'zod';

export const societyIdParamSchema = z.object({
  societyId: z.string().min(1),
});
