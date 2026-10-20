/**
 * Admin read-heavy endpoints (dashboard, reports, wings, facilities).
 * Requires LOAD_TEST_ACCESS_TOKEN (admin JWT) from a staging login.
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { resolveProfile, stagesFor } from '../config.js';

const profile = resolveProfile();
const token = __ENV.LOAD_TEST_ACCESS_TOKEN || '';

export const options = {
  stages: stagesFor(profile),
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2500'],
  },
  tags: { scenario: 'admin-reads', profile: profile.name },
};

export default function () {
  if (!token) {
    const res = http.get(`${profile.baseUrl}/api/v1/ready`);
    check(res, { ready: (r) => r.status === 200 || r.status === 503 });
    sleep(0.3);
    return;
  }

  const headers = { Authorization: `Bearer ${token}` };
  const paths = [
    '/api/v1/admin/dashboard',
    '/api/v1/admin/wings',
    '/api/v1/admin/reports/dashboard',
    '/api/v1/admin/reports/financial',
    '/api/v1/admin/reports/collections',
    '/api/v1/admin/facilities',
    '/api/v1/admin/ops/metrics',
  ];

  for (const path of paths) {
    const res = http.get(`${profile.baseUrl}${path}`, { headers });
    check(res, { [`${path} ok`]: (r) => r.status === 200 || r.status === 401 || r.status === 403 });
  }
  sleep(0.4);
}
