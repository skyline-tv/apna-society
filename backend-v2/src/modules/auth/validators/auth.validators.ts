import { z } from 'zod';

export const requestOtpSchema = z.object({
  email: z.string().email('Valid email is required').max(254),
});

export const verifyOtpSchema = z.object({
  email: z.string().email('Valid email is required').max(254),
  otp: z
    .string()
    .trim()
    .regex(/^\d{6}$/, 'OTP must be a 6-digit code'),
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(20, 'Refresh token is required'),
});

export const logoutSchema = z.object({
  refreshToken: z.string().min(20).optional(),
});

export type RequestOtpInput = z.infer<typeof requestOtpSchema>;
export type VerifyOtpInput = z.infer<typeof verifyOtpSchema>;
export type RefreshInput = z.infer<typeof refreshSchema>;
