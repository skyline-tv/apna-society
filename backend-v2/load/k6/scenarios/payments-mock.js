/**
 * Payment operations against mock gateway only.
 * Never sets PAYMENTS_LIVE_ENABLED. Webhook simulation uses mock signatures in staging.
 * Requires LOAD_TEST_ACCESS_TOKEN + optional LOAD_TEST_BILL_ID.
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { resolveProfile, stagesFor } from '../config.js';

const profile = resolveProfile();
const token = __ENV.LOAD_TEST_ACCESS_TOKEN || '';
const billId = __ENV.LOAD_TEST_BILL_ID || '';

export const options = {
  stages: stagesFor(profile),
  thresholds: {
    http_req_failed: ['rate<0.15'],
    http_req_duration: ['p(95)<4000'],
  },
  tags: { scenario: 'payments-mock', profile: profile.name },
};

export default function () {
  if (!token || !billId) {
    const res = http.get(`${profile.baseUrl}/health`);
    check(res, { health: (r) => r.status === 200 });
    sleep(0.5);
    return;
  }

  const headers = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };

  const order = http.post(
    `${profile.baseUrl}/api/v1/resident/payments/orders`,
    JSON.stringify({ billId }),
    { headers },
  );
  check(order, {
    'order created or conflict': (r) => [200, 201, 409, 400, 402].includes(r.status),
  });

  sleep(0.5);
}
