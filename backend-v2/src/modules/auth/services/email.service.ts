import { Resend } from 'resend';
import { getEnv } from '../../../config/env';
import { getLogger } from '../../../utils/logger';

export interface EmailService {
  sendOtpEmail(to: string, otp: string): Promise<void>;
  sendVisitorEntryOtpEmail(input: {
    to: string;
    otp: string;
    visitorName: string;
    flatLabel: string;
  }): Promise<void>;
}

class ResendEmailService implements EmailService {
  private client: Resend | null = null;

  private getClient(): Resend {
    if (!this.client) {
      const apiKey = getEnv().RESEND_API_KEY;
      if (!apiKey) {
        throw new Error('RESEND_API_KEY is not configured');
      }
      this.client = new Resend(apiKey);
    }
    return this.client;
  }

  private assertCanSend(to: string): boolean {
    const env = getEnv();
    const logger = getLogger();
    if (env.NODE_ENV === 'test') {
      logger.debug({ to }, 'Skipped email send in test environment');
      return false;
    }
    if (!env.RESEND_API_KEY) {
      if (env.NODE_ENV === 'development') {
        logger.warn({ to }, 'RESEND_API_KEY missing; email not sent (secrets/OTP never logged)');
        return false;
      }
      throw new Error('Email delivery is not configured');
    }
    return true;
  }

  async sendOtpEmail(to: string, otp: string): Promise<void> {
    if (!this.assertCanSend(to)) return;
    const env = getEnv();
    const logger = getLogger();
    const result = await this.getClient().emails.send({
      from: env.EMAIL_FROM,
      to: [to],
      subject: 'Your Apna Society login code',
      text: `Your one-time login code is ${otp}. It expires in 5 minutes. If you did not request this, ignore this email.`,
      html: `<p>Your one-time login code is <strong>${otp}</strong>.</p><p>It expires in 5 minutes.</p><p>If you did not request this, ignore this email.</p>`,
    });
    if (result.error) {
      logger.error({ err: result.error, to }, 'Failed to send login OTP email');
      throw new Error('Failed to send OTP email');
    }
    logger.info({ to, emailId: result.data?.id }, 'Login OTP email accepted by provider');
  }

  async sendVisitorEntryOtpEmail(input: {
    to: string;
    otp: string;
    visitorName: string;
    flatLabel: string;
  }): Promise<void> {
    if (!this.assertCanSend(input.to)) return;
    const env = getEnv();
    const logger = getLogger();
    const result = await this.getClient().emails.send({
      from: env.EMAIL_FROM,
      to: [input.to],
      subject: `Visitor entry code for ${input.flatLabel}`,
      text: `Entry OTP for visitor ${input.visitorName} (${input.flatLabel}) is ${input.otp}. Share this code only with the gate security. It expires soon.`,
      html: `<p>Entry OTP for visitor <strong>${input.visitorName}</strong> at <strong>${input.flatLabel}</strong>:</p><p style="font-size:20px"><strong>${input.otp}</strong></p><p>Share this code only with gate security. It expires soon.</p>`,
    });
    if (result.error) {
      logger.error({ err: result.error, to: input.to }, 'Failed to send visitor OTP email');
      throw new Error('Failed to send visitor OTP email');
    }
    logger.info(
      { to: input.to, emailId: result.data?.id, flatLabel: input.flatLabel },
      'Visitor OTP email accepted by provider',
    );
  }
}

let emailService: EmailService = new ResendEmailService();

export function getEmailService(): EmailService {
  return emailService;
}

export function setEmailService(service: EmailService): void {
  emailService = service;
}

export function resetEmailService(): void {
  emailService = new ResendEmailService();
}
