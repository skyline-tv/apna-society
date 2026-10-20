import pino from 'pino';
import { getEnv } from '../config/env';

let logger: pino.Logger | null = null;

export function getLogger(): pino.Logger {
  if (!logger) {
    const env = getEnv();
    logger = pino({
      level: env.LOG_LEVEL,
      redact: {
        paths: [
          'req.headers.authorization',
          'req.headers.cookie',
          'req.body.otp',
          'req.body.password',
          'req.body.refreshToken',
          'req.body.accessToken',
          'req.body.signature',
          'otp',
          'otpHash',
          'entryOtpHash',
          'refreshToken',
          'tokenHash',
          'accessToken',
          'password',
          'RAZORPAY_KEY_SECRET',
          'RAZORPAY_WEBHOOK_SECRET',
          'RESEND_API_KEY',
          'JWT_ACCESS_SECRET',
          'JWT_REFRESH_SECRET',
          'S3_SECRET_ACCESS_KEY',
        ],
        remove: true,
      },
      transport:
        env.NODE_ENV === 'development'
          ? { target: 'pino-pretty', options: { colorize: true, translateTime: 'SYS:standard' } }
          : undefined,
    });
  }
  return logger;
}

export function resetLogger(): void {
  logger = null;
}
