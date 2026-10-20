export interface SmsSendOtpInput {
  mobileE164: string;
  otpLength: number;
  expiryMinutes: number;
  /** Optional caller IP for provider analytics. */
  userIp?: string;
}

export interface SmsSendOtpResult {
  requestId?: string;
  /** Present only for memory/dev providers — never returned to clients. */
  debugOtp?: string;
}

export interface SmsVerifyOtpInput {
  mobileE164: string;
  otp: string;
}

export interface SmsVerifyOtpResult {
  verified: boolean;
  reason?: 'INVALID' | 'EXPIRED' | 'PROVIDER_ERROR';
}

export interface SmsProvider {
  readonly name: string;
  sendOtp(input: SmsSendOtpInput): Promise<SmsSendOtpResult>;
  verifyOtp(input: SmsVerifyOtpInput): Promise<SmsVerifyOtpResult>;
  resendOtp?(input: { mobileE164: string; userIp?: string }): Promise<SmsSendOtpResult>;
}
