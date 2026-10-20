import { generateOtp, hashToken, safeEqualHex } from '../../../utils/crypto';
import type {
  SmsProvider,
  SmsSendOtpInput,
  SmsSendOtpResult,
  SmsVerifyOtpInput,
  SmsVerifyOtpResult,
} from './sms-provider';

interface MemoryChallenge {
  otpHash: string;
  expiresAt: number;
  otpPlainForTests: string;
}

/**
 * In-memory SMS OTP for local development and automated tests.
 * OTPs are never written to application logs.
 */
export class MemorySmsProvider implements SmsProvider {
  readonly name = 'memory';
  private readonly challenges = new Map<string, MemoryChallenge>();

  clear(): void {
    this.challenges.clear();
  }

  /** Test helper — returns plaintext OTP without logging. */
  peekOtp(mobileE164: string): string | undefined {
    return this.challenges.get(mobileE164)?.otpPlainForTests;
  }

  async sendOtp(input: SmsSendOtpInput): Promise<SmsSendOtpResult> {
    const otp = generateOtp(input.otpLength);
    this.challenges.set(input.mobileE164, {
      otpHash: hashToken(otp),
      expiresAt: Date.now() + input.expiryMinutes * 60_000,
      otpPlainForTests: otp,
    });
    return { requestId: `mem_${input.mobileE164}`, debugOtp: otp };
  }

  async resendOtp(input: { mobileE164: string }): Promise<SmsSendOtpResult> {
    return this.sendOtp({
      mobileE164: input.mobileE164,
      otpLength: 6,
      expiryMinutes: 5,
    });
  }

  async verifyOtp(input: SmsVerifyOtpInput): Promise<SmsVerifyOtpResult> {
    const challenge = this.challenges.get(input.mobileE164);
    if (!challenge) {
      return { verified: false, reason: 'INVALID' };
    }
    if (challenge.expiresAt <= Date.now()) {
      this.challenges.delete(input.mobileE164);
      return { verified: false, reason: 'EXPIRED' };
    }
    const ok = safeEqualHex(hashToken(input.otp), challenge.otpHash);
    if (!ok) {
      return { verified: false, reason: 'INVALID' };
    }
    this.challenges.delete(input.mobileE164);
    return { verified: true };
  }
}

let singleton: MemorySmsProvider | null = null;

export function getMemorySmsProvider(): MemorySmsProvider {
  if (!singleton) singleton = new MemorySmsProvider();
  return singleton;
}
