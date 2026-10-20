import type { Request, Response } from 'express';
import {
  changePassword,
  getProfile,
  loginWithPassword,
  logout,
  logoutAll,
  refreshTokens,
  requestOtp,
  verifyOtp,
} from '../services/auth.service';
import type {
  ChangePasswordInput,
  LoginInput,
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

export async function loginHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as LoginInput;
  const tokens = await loginWithPassword(body.username, body.password, metaFromRequest(req));
  res.status(200).json({ success: true, data: tokens });
}

export async function changePasswordHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as ChangePasswordInput;
  const result = await changePassword(
    req.user!.id,
    body.currentPassword,
    body.newPassword,
    metaFromRequest(req),
  );
  res.status(200).json({ success: true, data: result });
}

/** @deprecated Prefer username/password login. Kept for transitional rollback only. */
export async function requestOtpHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as RequestOtpInput;
  const result = await requestOtp(body.mobile, metaFromRequest(req));
  res.status(200).json({ success: true, data: result });
}

/** @deprecated Prefer username/password login. Kept for transitional rollback only. */
export async function verifyOtpHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as VerifyOtpInput;
  const tokens = await verifyOtp(body.mobile, body.otp, metaFromRequest(req));
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
