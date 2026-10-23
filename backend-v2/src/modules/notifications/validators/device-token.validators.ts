import { z } from 'zod';
import { DEVICE_PLATFORMS } from '../models/device-token.model';

export const registerDeviceTokenSchema = z
  .object({
    token: z.string().trim().min(16).max(4096),
    platform: z.enum(DEVICE_PLATFORMS),
    deviceId: z.string().trim().min(1).max(128).optional(),
  })
  .strict();

export const unregisterDeviceTokenSchema = z
  .object({
    token: z.string().trim().min(16).max(4096),
  })
  .strict();

export type RegisterDeviceTokenInput = z.infer<typeof registerDeviceTokenSchema>;
export type UnregisterDeviceTokenInput = z.infer<typeof unregisterDeviceTokenSchema>;
