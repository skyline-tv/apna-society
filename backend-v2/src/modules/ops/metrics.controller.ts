import type { Request, Response } from 'express';
import { getOpsMetricsSnapshot } from './metrics.service';

/** Admin-only operational metrics (HTTP, cache, Redis, Mongo pool hints). */
export async function opsMetricsHandler(_req: Request, res: Response): Promise<void> {
  res.json({ success: true, data: getOpsMetricsSnapshot() });
}
