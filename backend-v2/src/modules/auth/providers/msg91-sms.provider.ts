import { getEnv } from '../../../config/env';
import { badRequest, tooManyRequests } from '../../../shared/errors/app-error';
import { getLogger } from '../../../utils/logger';
import type {
  SmsProvider,
  SmsSendOtpInput,
  SmsSendOtpResult,
  SmsVerifyOtpInput,
  SmsVerifyOtpResult,
} from './sms-provider';

type Msg91Json = {
  type?: string;
  message?: string | Record<string, unknown>;
  request_id?: string;
  code?: string | number;
};

/** MSG91 discards duplicate OTP sends to the same mobile within ~10s. */
const MSG91_DUPLICATE_WINDOW_MS = 12_000;

const lastSendByMobile = new Map<string, number>();

function providerMessageText(body: Msg91Json): string {
  return typeof body.message === 'string' ? body.message : '';
}

function isDuplicateDiscardMessage(message: string): boolean {
  const m = message.toLowerCase();
  return (
    m.includes('same request was generated twice') ||
    m.includes('request discarded because same request') ||
    (m.includes('discarded') && m.includes('10 second'))
  );
}

/**
 * MSG91 OTP API v5 (control.msg91.com).
 * Send: POST /api/v5/otp
 * Verify: GET /api/v5/otp/verify
 * Resend: POST /api/v5/otp/retry
 *
 * Credentials stay server-side. OTP values are never logged.
 */
export class Msg91SmsProvider implements SmsProvider {
  readonly name = 'msg91';

  private baseUrl(): string {
    const env = getEnv();
    const raw = (env.MSG91_BASE_URL || 'https://control.msg91.com/api/v5').replace(/\/+$/, '');
    return raw;
  }

  private authKey(): string {
    const key = getEnv().MSG91_AUTH_KEY?.trim();
    if (!key) {
      throw badRequest('MSG91 is not configured', 'SMS_NOT_CONFIGURED');
    }
    return key;
  }

  private templateId(): string {
    const id = getEnv().MSG91_TEMPLATE_ID?.trim();
    if (!id) {
      throw badRequest('MSG91 template is not configured', 'SMS_NOT_CONFIGURED');
    }
    return id;
  }

  private async parseJson(response: Response): Promise<Msg91Json> {
    const text = await response.text();
    try {
      return JSON.parse(text) as Msg91Json;
    } catch {
      return { type: 'error', message: text.slice(0, 200) };
    }
  }

  private isSuccess(body: Msg91Json, httpOk: boolean): boolean {
    if (!httpOk) return false;
    if (body.type === 'error' || String(body.code) === '201') return false;
    if (isDuplicateDiscardMessage(providerMessageText(body))) return false;
    return body.type === 'success' || httpOk;
  }

  private assertNotInDuplicateWindow(mobileE164: string): void {
    const last = lastSendByMobile.get(mobileE164);
    if (last !== undefined && Date.now() - last < MSG91_DUPLICATE_WINDOW_MS) {
      throw tooManyRequests(
        'Please wait a few seconds before requesting another code',
        'OTP_COOLDOWN',
      );
    }
  }

  async sendOtp(input: SmsSendOtpInput): Promise<SmsSendOtpResult> {
    const logger = getLogger();
    const env = getEnv();
    this.assertNotInDuplicateWindow(input.mobileE164);

    const url = new URL(`${this.baseUrl()}/otp`);
    url.searchParams.set('template_id', this.templateId());
    url.searchParams.set('mobile', input.mobileE164);
    url.searchParams.set('otp_length', String(input.otpLength));
    url.searchParams.set('otp_expiry', String(input.expiryMinutes));
    url.searchParams.set('realTimeResponse', '1');
    if (input.userIp) url.searchParams.set('userip', input.userIp);
    if (env.MSG91_SENDER_ID) {
      // Sender is usually bound to the OTP template; include when provided.
      url.searchParams.set('sender', env.MSG91_SENDER_ID);
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15_000);
    try {
      const response = await fetch(url.toString(), {
        method: 'POST',
        headers: {
          authkey: this.authKey(),
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify({}),
        signal: controller.signal,
      });
      const body = await this.parseJson(response);
      const providerMessage = providerMessageText(body).slice(0, 200);

      if (isDuplicateDiscardMessage(providerMessage)) {
        logger.warn(
          { provider: 'msg91', mobileSuffix: input.mobileE164.slice(-4) },
          'MSG91 discarded duplicate OTP send',
        );
        throw tooManyRequests(
          'Please wait a few seconds before requesting another code',
          'OTP_COOLDOWN',
        );
      }

      if (!this.isSuccess(body, response.ok)) {
        logger.error(
          {
            provider: 'msg91',
            status: response.status,
            type: body.type,
            code: body.code,
            providerMessage: providerMessage || undefined,
          },
          'MSG91 send OTP failed',
        );
        throw badRequest('Unable to send OTP right now. Try again later.', 'SMS_SEND_FAILED');
      }

      lastSendByMobile.set(input.mobileE164, Date.now());
      logger.info(
        { provider: 'msg91', mobileSuffix: input.mobileE164.slice(-4), requestId: body.request_id },
        'MSG91 OTP accepted',
      );
      return { requestId: body.request_id };
    } catch (error) {
      if ((error as { name?: string }).name === 'AbortError') {
        logger.error({ provider: 'msg91' }, 'MSG91 send OTP timed out');
        throw badRequest('SMS provider timed out. Try again later.', 'SMS_TIMEOUT');
      }
      throw error;
    } finally {
      clearTimeout(timeout);
    }
  }

  async resendOtp(input: { mobileE164: string; userIp?: string }): Promise<SmsSendOtpResult> {
    const logger = getLogger();
    const url = new URL(`${this.baseUrl()}/otp/retry`);
    url.searchParams.set('authkey', this.authKey());
    url.searchParams.set('mobile', input.mobileE164);
    url.searchParams.set('retrytype', 'text');
    if (input.userIp) url.searchParams.set('userip', input.userIp);

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15_000);
    try {
      const response = await fetch(url.toString(), {
        method: 'POST',
        headers: {
          authkey: this.authKey(),
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify({}),
        signal: controller.signal,
      });
      const body = await this.parseJson(response);
      if (!this.isSuccess(body, response.ok)) {
        logger.error(
          { provider: 'msg91', status: response.status, type: body.type },
          'MSG91 resend OTP failed',
        );
        throw badRequest('Unable to resend OTP right now. Try again later.', 'SMS_SEND_FAILED');
      }
      return { requestId: body.request_id };
    } catch (error) {
      if ((error as { name?: string }).name === 'AbortError') {
        throw badRequest('SMS provider timed out. Try again later.', 'SMS_TIMEOUT');
      }
      throw error;
    } finally {
      clearTimeout(timeout);
    }
  }

  async verifyOtp(input: SmsVerifyOtpInput): Promise<SmsVerifyOtpResult> {
    const logger = getLogger();
    const url = new URL(`${this.baseUrl()}/otp/verify`);
    url.searchParams.set('mobile', input.mobileE164);
    url.searchParams.set('otp', input.otp);

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15_000);
    try {
      const response = await fetch(url.toString(), {
        method: 'GET',
        headers: {
          authkey: this.authKey(),
          Accept: 'application/json',
        },
        signal: controller.signal,
      });
      const body = await this.parseJson(response);
      const message =
        typeof body.message === 'string' ? body.message.toLowerCase() : '';

      if (message.includes('expired')) {
        return { verified: false, reason: 'EXPIRED' };
      }
      if (
        this.isSuccess(body, response.ok) ||
        message.includes('verified success') ||
        message.includes('otp verified')
      ) {
        return { verified: true };
      }
      if (body.type === 'error' || message.includes('invalid')) {
        return { verified: false, reason: 'INVALID' };
      }
      logger.error(
        { provider: 'msg91', status: response.status, type: body.type },
        'MSG91 verify OTP unexpected response',
      );
      return { verified: false, reason: 'PROVIDER_ERROR' };
    } catch (error) {
      if ((error as { name?: string }).name === 'AbortError') {
        logger.error({ provider: 'msg91' }, 'MSG91 verify OTP timed out');
        return { verified: false, reason: 'PROVIDER_ERROR' };
      }
      throw error;
    } finally {
      clearTimeout(timeout);
    }
  }
}
