import { getEnv } from '../../../config/env';
import { badRequest } from '../../../shared/errors/app-error';
import { getDevBypassSmsProvider } from './dev-bypass-sms.provider';
import { getMemorySmsProvider } from './memory-sms.provider';
import { Msg91SmsProvider } from './msg91-sms.provider';
import type { SmsProvider } from './sms-provider';

let override: SmsProvider | null = null;

export function setSmsProviderForTests(provider: SmsProvider | null): void {
  override = provider;
}

/**
 * Resolves the SMS OTP provider.
 * When SMS_OTP_DEV_BYPASS=true (non-production), uses fixed OTP 123456 and never calls MSG91.
 * When SMS_OTP_ENABLED=false, uses the memory provider so local/dev/CI never call MSG91.
 */
export function getSmsProvider(): SmsProvider {
  if (override) return override;
  const env = getEnv();
  if (env.SMS_OTP_DEV_BYPASS && env.NODE_ENV !== 'production') {
    return getDevBypassSmsProvider();
  }
  if (!env.SMS_OTP_ENABLED || env.SMS_PROVIDER === 'memory' || env.NODE_ENV === 'test') {
    return getMemorySmsProvider();
  }
  if (env.SMS_PROVIDER === 'msg91') {
    return new Msg91SmsProvider();
  }
  throw badRequest('Unsupported SMS provider', 'SMS_PROVIDER_UNSUPPORTED');
}
