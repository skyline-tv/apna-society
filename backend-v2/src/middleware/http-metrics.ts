import type { NextFunction, Request, Response } from 'express';

type HttpMetricsState = {
  requestCount: number;
  errorCount: number;
  durationMsTotal: number;
  durationMsCount: number;
  byPath: Map<string, { count: number; errors: number; durationMsTotal: number }>;
};

const state: HttpMetricsState = {
  requestCount: 0,
  errorCount: 0,
  durationMsTotal: 0,
  durationMsCount: 0,
  byPath: new Map(),
};

function normalizePath(path: string): string {
  return path
    .replace(/\/[a-f\d]{24}/gi, '/:id')
    .replace(/\/\d+/g, '/:n')
    .slice(0, 120);
}

export function httpMetricsMiddleware(req: Request, res: Response, next: NextFunction): void {
  const start = performance.now();
  res.on('finish', () => {
    const duration = performance.now() - start;
    const path = normalizePath(req.route?.path ? `${req.baseUrl}${req.route.path}` : req.path);
    state.requestCount += 1;
    state.durationMsTotal += duration;
    state.durationMsCount += 1;
    const isError = res.statusCode >= 500;
    if (isError) state.errorCount += 1;

    const row = state.byPath.get(path) ?? { count: 0, errors: 0, durationMsTotal: 0 };
    row.count += 1;
    row.durationMsTotal += duration;
    if (isError) row.errors += 1;
    state.byPath.set(path, row);
  });
  next();
}

export function getHttpMetrics() {
  const avgDurationMs =
    state.durationMsCount === 0 ? 0 : state.durationMsTotal / state.durationMsCount;
  const slowest = [...state.byPath.entries()]
    .map(([path, row]) => ({
      path,
      count: row.count,
      errors: row.errors,
      avgDurationMs: row.count === 0 ? 0 : row.durationMsTotal / row.count,
    }))
    .sort((a, b) => b.avgDurationMs - a.avgDurationMs)
    .slice(0, 20);

  return {
    requestCount: state.requestCount,
    errorCount: state.errorCount,
    avgDurationMs,
    slowestEndpoints: slowest,
  };
}

export function resetHttpMetrics(): void {
  state.requestCount = 0;
  state.errorCount = 0;
  state.durationMsTotal = 0;
  state.durationMsCount = 0;
  state.byPath.clear();
}
