import { z } from 'zod';

export const requestOtpSchema = z.object({
  mobile: z.string().trim().min(8).max(20),
});

export const verifyOtpSchema = z.object({
  mobile: z.string().trim().min(8).max(20),
  otp: z
    .string()
    .trim()
    .regex(/^\d{4,9}$/, 'OTP must be a numeric code'),
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
