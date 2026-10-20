/**
 * Resident activity — dashboard-ish reads.
 * Requires LOAD_TEST_ACCESS_TOKEN for a resident JWT.
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
  tags: { scenario: 'resident-reads', profile: profile.name },
};

export default function () {
  if (!token) {
    const res = http.get(`${profile.baseUrl}/health`);
    check(res, { health: (r) => r.status === 200 });
    sleep(0.3);
    return;
  }

  const headers = { Authorization: `Bearer ${token}` };
  const paths = [
    '/api/v1/resident/bills',
    '/api/v1/resident/payments',
    '/api/v1/resident/announcements',
    '/api/v1/resident/complaints',
    '/api/v1/resident/facilities',
  ];

  for (const path of paths) {
    const res = http.get(`${profile.baseUrl}${path}`, { headers });
    check(res, { [`${path}`]: (r) => r.status === 200 || r.status === 401 || r.status === 404 });
  }
  sleep(0.4);
}
