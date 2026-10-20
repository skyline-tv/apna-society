import { getEnv } from '../../../config/env';

/** Fixed OTP used when SMS_OTP_DEV_BYPASS is enabled (never in production). */
export const DEV_BYPASS_OTP = '123456';

export function isOtpDevBypassEnabled(): boolean {
  const env = getEnv();
  return Boolean(env.SMS_OTP_DEV_BYPASS && env.NODE_ENV !== 'production');
}
