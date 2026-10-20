import http from 'k6/http';
import { check, sleep } from 'k6';
import { resolveProfile, stagesFor } from '../config.js';

const profile = resolveProfile();

export const options = {
  stages: stagesFor(profile),
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2000'],
  },
  tags: { scenario: 'health', profile: profile.name },
};

export default function () {
  const res = http.get(`${profile.baseUrl}/api/v1/ready`);
  check(res, { 'ready ok': (r) => r.status === 200 || r.status === 503 });
  sleep(0.2);
}
