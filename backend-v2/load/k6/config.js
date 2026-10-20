/**
 * Shared k6 profile configuration.
 * Override with env: PROFILE, VUS, DURATION, RAMP, BASE_URL
 * Never point BASE_URL at production by default.
 */
export const profiles = {
  smoke: { vus: 5, duration: '30s', ramp: '5s' },
  normal: { vus: 50, duration: '2m', ramp: '30s' },
  stress: { vus: 150, duration: '3m', ramp: '45s' },
  spike: { vus: 200, duration: '1m', ramp: '5s' },
  soak: { vus: 40, duration: '15m', ramp: '1m' },
};

export function resolveProfile() {
  const name = __ENV.PROFILE || 'smoke';
  const base = profiles[name] || profiles.smoke;
  return {
    name,
    vus: Number(__ENV.VUS || base.vus),
    duration: __ENV.DURATION || base.duration,
    ramp: __ENV.RAMP || base.ramp,
    baseUrl: (__ENV.BASE_URL || 'http://127.0.0.1:4000').replace(/\/$/, ''),
  };
}

export function stagesFor(profile) {
  return [
    { duration: profile.ramp, target: profile.vus },
    { duration: profile.duration, target: profile.vus },
    { duration: profile.ramp, target: 0 },
  ];
}
