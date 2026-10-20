import type { Request, Response } from 'express';
import {
  getProfile,
  logout,
  logoutAll,
  refreshTokens,
  requestOtp,
  verifyOtp,
} from '../services/auth.service';
import type {
  RefreshInput,
  RequestOtpInput,
  VerifyOtpInput,
} from '../validators/auth.validators';

function metaFromRequest(req: Request) {
  return {
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? undefined,
  };
}

export async function requestOtpHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as RequestOtpInput;
  const result = await requestOtp(body.email, metaFromRequest(req));
  res.status(200).json({ success: true, data: result });
}

export async function verifyOtpHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as VerifyOtpInput;
  const tokens = await verifyOtp(body.email, body.otp, metaFromRequest(req));
  res.status(200).json({ success: true, data: tokens });
}

export async function refreshHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as RefreshInput;
  const tokens = await refreshTokens(body.refreshToken, metaFromRequest(req));
  res.status(200).json({ success: true, data: tokens });
}

export async function logoutHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as { refreshToken?: string };
  await logout(body.refreshToken, metaFromRequest(req));
  res.status(200).json({ success: true, data: { message: 'Logged out' } });
}

export async function logoutAllHandler(req: Request, res: Response): Promise<void> {
  const userId = req.user!.id;
  const result = await logoutAll(userId, metaFromRequest(req));
  res.status(200).json({ success: true, data: result });
}

export async function meHandler(req: Request, res: Response): Promise<void> {
  const profile = await getProfile(req.user!.id);
  res.status(200).json({ success: true, data: profile });
}
