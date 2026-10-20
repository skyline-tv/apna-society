/**
 * Auth scenario — requires LOAD_TEST_EMAIL (seeded user).
 * OTP verification is skipped unless LOAD_TEST_OTP is provided (staging only).
 * Never use production credentials.
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { resolveProfile, stagesFor } from '../config.js';

const profile = resolveProfile();
const email = __ENV.LOAD_TEST_EMAIL || '';

export const options = {
  stages: stagesFor(profile),
  thresholds: {
    http_req_failed: ['rate<0.1'],
    http_req_duration: ['p(95)<3000'],
  },
  tags: { scenario: 'auth', profile: profile.name },
};

export default function () {
  if (!email) {
    const res = http.get(`${profile.baseUrl}/health`);
    check(res, { health: (r) => r.status === 200 });
    sleep(0.5);
    return;
  }

  const start = http.post(
    `${profile.baseUrl}/api/v1/auth/otp/start`,
    JSON.stringify({ email }),
    { headers: { 'Content-Type': 'application/json' } },
  );
  check(start, { 'otp start': (r) => r.status === 200 || r.status === 429 });

  if (__ENV.LOAD_TEST_OTP) {
    const verify = http.post(
      `${profile.baseUrl}/api/v1/auth/otp/verify`,
      JSON.stringify({ email, otp: __ENV.LOAD_TEST_OTP }),
      { headers: { 'Content-Type': 'application/json' } },
    );
    check(verify, { 'otp verify': (r) => r.status === 200 || r.status === 400 });
  }

  sleep(0.5);
}
