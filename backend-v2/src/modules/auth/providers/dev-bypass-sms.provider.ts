import { DEV_BYPASS_OTP } from './otp-dev-bypass';
import type {
  SmsProvider,
  SmsSendOtpInput,
  SmsSendOtpResult,
  SmsVerifyOtpInput,
  SmsVerifyOtpResult,
} from './sms-provider';

export { DEV_BYPASS_OTP };

/**
 * Development SMS bypass: no MSG91 calls. Request is a no-op; verify accepts 123456.
 */
export class DevBypassSmsProvider implements SmsProvider {
  readonly name = 'dev-bypass';

  async sendOtp(input: SmsSendOtpInput): Promise<SmsSendOtpResult> {
    return {
      requestId: `dev_bypass_${input.mobileE164}`,
      debugOtp: DEV_BYPASS_OTP,
    };
  }

  async resendOtp(input: { mobileE164: string }): Promise<SmsSendOtpResult> {
    return this.sendOtp({
      mobileE164: input.mobileE164,
      otpLength: 6,
      expiryMinutes: 5,
    });
  }

  async verifyOtp(input: SmsVerifyOtpInput): Promise<SmsVerifyOtpResult> {
    if (input.otp === DEV_BYPASS_OTP) {
      return { verified: true };
    }
    return { verified: false, reason: 'INVALID' };
  }
}

let singleton: DevBypassSmsProvider | null = null;

export function getDevBypassSmsProvider(): DevBypassSmsProvider {
  if (!singleton) singleton = new DevBypassSmsProvider();
  return singleton;
}
