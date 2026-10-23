import type { Request, Response } from 'express';
import {
  registerDeviceToken,
  unregisterDeviceToken,
} from '../services/device-token.service';
import type {
  RegisterDeviceTokenInput,
  UnregisterDeviceTokenInput,
} from '../validators/device-token.validators';

function societyId(req: Request): string {
  return String(req.societyId);
}

export async function registerDeviceTokenHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as RegisterDeviceTokenInput;
  const data = await registerDeviceToken({
    userId: req.user!.id,
    societyId: societyId(req),
    token: body.token,
    platform: body.platform,
    deviceId: body.deviceId,
  });
  res.status(201).json({ success: true, data });
}

export async function unregisterDeviceTokenHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as UnregisterDeviceTokenInput;
  const data = await unregisterDeviceToken({
    userId: req.user!.id,
    token: body.token,
  });
  res.json({ success: true, data });
}
