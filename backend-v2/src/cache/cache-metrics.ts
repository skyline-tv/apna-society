export type CacheMetricsSnapshot = {
  hits: number;
  misses: number;
  errors: number;
  invalidations: number;
  sets: number;
  getLatencyMsTotal: number;
  getLatencyMsCount: number;
  setLatencyMsTotal: number;
  setLatencyMsCount: number;
  hitRatio: number;
  avgGetLatencyMs: number;
  avgSetLatencyMs: number;
};

const state = {
  hits: 0,
  misses: 0,
  errors: 0,
  invalidations: 0,
  sets: 0,
  getLatencyMsTotal: 0,
  getLatencyMsCount: 0,
  setLatencyMsTotal: 0,
  setLatencyMsCount: 0,
};

export function recordCacheHit(latencyMs: number): void {
  state.hits += 1;
  state.getLatencyMsTotal += latencyMs;
  state.getLatencyMsCount += 1;
}

export function recordCacheMiss(latencyMs: number): void {
  state.misses += 1;
  state.getLatencyMsTotal += latencyMs;
  state.getLatencyMsCount += 1;
}

export function recordCacheError(): void {
  state.errors += 1;
}

export function recordCacheSet(latencyMs: number): void {
  state.sets += 1;
  state.setLatencyMsTotal += latencyMs;
  state.setLatencyMsCount += 1;
}

export function recordCacheInvalidation(count = 1): void {
  state.invalidations += count;
}

export function getCacheMetrics(): CacheMetricsSnapshot {
  const lookedUp = state.hits + state.misses;
  return {
    ...state,
    hitRatio: lookedUp === 0 ? 0 : state.hits / lookedUp,
    avgGetLatencyMs:
      state.getLatencyMsCount === 0 ? 0 : state.getLatencyMsTotal / state.getLatencyMsCount,
    avgSetLatencyMs:
      state.setLatencyMsCount === 0 ? 0 : state.setLatencyMsTotal / state.setLatencyMsCount,
  };
}

export function resetCacheMetrics(): void {
  state.hits = 0;
  state.misses = 0;
  state.errors = 0;
  state.invalidations = 0;
  state.sets = 0;
  state.getLatencyMsTotal = 0;
  state.getLatencyMsCount = 0;
  state.setLatencyMsTotal = 0;
  state.setLatencyMsCount = 0;
}
