import { afterEach, describe, expect, it, vi } from 'vitest';
import { Msg91SmsProvider } from '../../src/modules/auth/providers/msg91-sms.provider';
import { resetEnvCache, loadEnv } from '../../src/config/env';

describe('Msg91SmsProvider', () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
    process.env.SMS_OTP_ENABLED = 'false';
    process.env.MSG91_AUTH_KEY = '';
    process.env.MSG91_TEMPLATE_ID = '';
    resetEnvCache();
    loadEnv();
  });

  function enableMsg91Env() {
    process.env.SMS_OTP_ENABLED = 'true';
    process.env.SMS_PROVIDER = 'msg91';
    process.env.MSG91_AUTH_KEY = 'test-auth-key-xxxxxxxx';
    process.env.MSG91_TEMPLATE_ID = 'template-id-test';
    process.env.MSG91_SENDER_ID = 'APNASO';
    process.env.MSG91_BASE_URL = 'https://control.msg91.com/api/v5';
    resetEnvCache();
    loadEnv();
  }

  it('maps provider API failure to SMS_SEND_FAILED without leaking secrets', async () => {
    enableMsg91Env();
    globalThis.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ type: 'error', message: 'auth failed', code: '201' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    ) as typeof fetch;

    const provider = new Msg91SmsProvider();
    await expect(
      provider.sendOtp({
        mobileE164: '919876543210',
        otpLength: 6,
        expiryMinutes: 5,
      }),
    ).rejects.toMatchObject({ code: 'SMS_SEND_FAILED' });

    const call = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
    const headers = call[1]?.headers as Record<string, string>;
    expect(headers.authkey).toBe('test-auth-key-xxxxxxxx');
    expect(JSON.stringify(call)).not.toMatch(/otpPlain|debugOtp/);
  });

  it('maps AbortError to SMS_TIMEOUT', async () => {
    enableMsg91Env();
    globalThis.fetch = vi.fn(async () => {
      const err = new Error('aborted');
      err.name = 'AbortError';
      throw err;
    }) as typeof fetch;

    const provider = new Msg91SmsProvider();
    await expect(
      provider.sendOtp({
        mobileE164: '919876543210',
        otpLength: 6,
        expiryMinutes: 5,
      }),
    ).rejects.toMatchObject({ code: 'SMS_TIMEOUT' });
  });

  it('verifies OTP via MSG91 verify endpoint', async () => {
    enableMsg91Env();
    globalThis.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ type: 'success', message: 'OTP verified success' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    ) as typeof fetch;

    const provider = new Msg91SmsProvider();
    const result = await provider.verifyOtp({
      mobileE164: '919876543210',
      otp: '123456',
    });
    expect(result.verified).toBe(true);
    const url = String((globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0][0]);
    expect(url).toContain('/otp/verify');
    expect(url).toContain('mobile=919876543210');
    expect(url).toContain('otp=123456');
  });

  it('returns INVALID for wrong OTP responses', async () => {
    enableMsg91Env();
    globalThis.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ type: 'error', message: 'OTP not match / Invalid OTP' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    ) as typeof fetch;

    const provider = new Msg91SmsProvider();
    const result = await provider.verifyOtp({
      mobileE164: '919876543210',
      otp: '000000',
    });
    expect(result).toEqual({ verified: false, reason: 'INVALID' });
  });
});
