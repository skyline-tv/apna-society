import { z } from 'zod';
import { PASSWORD_MAX_LENGTH, PASSWORD_MIN_LENGTH } from '../../../utils/password';
import { USERNAME_MAX_LENGTH, USERNAME_MIN_LENGTH } from '../../../utils/username';

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

export const loginSchema = z
  .object({
    username: z
      .string()
      .trim()
      .min(USERNAME_MIN_LENGTH)
      .max(USERNAME_MAX_LENGTH),
    password: z.string().min(1).max(PASSWORD_MAX_LENGTH),
  })
  .strict();

export const changePasswordSchema = z
  .object({
    currentPassword: z.string().min(1).max(PASSWORD_MAX_LENGTH),
    newPassword: z.string().min(PASSWORD_MIN_LENGTH).max(PASSWORD_MAX_LENGTH),
    confirmPassword: z.string().min(PASSWORD_MIN_LENGTH).max(PASSWORD_MAX_LENGTH),
  })
  .strict()
  .refine((data) => data.newPassword === data.confirmPassword, {
    message: 'Password confirmation does not match',
    path: ['confirmPassword'],
  });

export const refreshSchema = z.object({
  refreshToken: z.string().min(20, 'Refresh token is required'),
});

export const logoutSchema = z.object({
  refreshToken: z.string().min(20).optional(),
});

export type RequestOtpInput = z.infer<typeof requestOtpSchema>;
export type VerifyOtpInput = z.infer<typeof verifyOtpSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
export type ChangePasswordInput = z.infer<typeof changePasswordSchema>;
export type RefreshInput = z.infer<typeof refreshSchema>;
