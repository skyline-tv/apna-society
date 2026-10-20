import rateLimit from 'express-rate-limit';
import { getEnv } from '../config/env';

export const globalRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'RATE_LIMITED',
      message: 'Too many requests, please try again later',
    },
  },
  skip: () => getEnv().NODE_ENV === 'test',
});

export const authRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 40,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'RATE_LIMITED',
      message: 'Too many authentication attempts, please try again later',
    },
  },
  skip: () => getEnv().NODE_ENV === 'test',
});

export const visitorOtpRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'RATE_LIMITED',
      message: 'Too many OTP verification attempts, please try again later',
    },
  },
  skip: () => getEnv().NODE_ENV === 'test',
});

export const complaintCreateRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 40,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'RATE_LIMITED',
      message: 'Too many complaint submissions, please try again later',
    },
  },
  skip: () => getEnv().NODE_ENV === 'test',
});

export const complaintUploadRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'RATE_LIMITED',
      message: 'Too many attachment uploads, please try again later',
    },
  },
  skip: () => getEnv().NODE_ENV === 'test',
});

export const announcementPublishRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 40,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'RATE_LIMITED',
      message: 'Too many announcement publication attempts, please try again later',
    },
  },
  skip: () => getEnv().NODE_ENV === 'test',
});

export const announcementUploadRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'RATE_LIMITED',
      message: 'Too many announcement attachment uploads, please try again later',
    },
  },
  skip: () => getEnv().NODE_ENV === 'test',
});
