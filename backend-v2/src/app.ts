import cookieParser from 'cookie-parser';
import cors from 'cors';
import express, { type Request } from 'express';
import helmet from 'helmet';
import pinoHttp from 'pino-http';
import swaggerUi from 'swagger-ui-express';
import { API_PREFIX } from './config/constants';
import { DEMO_MODE_LABEL, isDemoMode } from './config/demo';
import { getCorsOrigins, getEnv, isDemoPaymentsEnabled } from './config/env';
import { getDatabaseHealth, pingDatabase } from './database/connection';
import { buildOpenApiSpec } from './docs/openapi';
import { errorHandler, notFoundHandler } from './middleware/error-handler';
import { httpMetricsMiddleware } from './middleware/http-metrics';
import { globalRateLimiter } from './middleware/rate-limit';
import { requestIdMiddleware } from './middleware/request-id';
import authRoutes from './modules/auth/routes/auth.routes';
import webhookRoutes from './modules/billing/routes/webhook.routes';
import adminRoutes from './modules/society/routes/admin.routes';
import societyRoutes from './modules/society/routes/society.routes';
import residentRoutes from './modules/users/routes/resident.routes';
import usersRoutes from './modules/users/routes/users.routes';
import guardRoutes from './modules/visitors/routes/guard.routes';
import meRoutes from './modules/notifications/routes/me.routes';
import { getLogger } from './utils/logger';

export function createApp() {
  const env = getEnv();
  const app = express();

  app.set('trust proxy', 1);
  app.use(requestIdMiddleware);
  app.use(httpMetricsMiddleware);
  app.use(
    pinoHttp({
      logger: getLogger(),
      customProps: (req) => ({ requestId: req.requestId }),
      autoLogging: env.NODE_ENV !== 'test',
    }),
  );
  app.use(
    helmet({
      contentSecurityPolicy: env.NODE_ENV === 'production' ? undefined : false,
    }),
  );
  app.use(
    cors({
      origin: getCorsOrigins(env),
      credentials: true,
    }),
  );
  app.use(
    express.json({
      limit: '1mb',
      verify: (req, _res, buf) => {
        (req as Request & { rawBody?: string }).rawBody = buf.toString('utf8');
      },
    }),
  );
  app.use(express.urlencoded({ extended: false }));
  app.use(cookieParser());
  app.use(globalRateLimiter);

  app.get('/health', (_req, res) => {
    res.status(200).json({
      success: true,
      data: {
        status: 'ok',
        service: 'apna-society-backend-v2',
        demoMode: isDemoMode(),
        timestamp: new Date().toISOString(),
      },
    });
  });

  app.get(`${API_PREFIX}/public/environment`, (_req, res) => {
    const demo = isDemoMode();
    res.status(200).json({
      success: true,
      data: {
        demoMode: demo,
        label: demo ? DEMO_MODE_LABEL : undefined,
        simulatedPayments: demo && isDemoPaymentsEnabled(),
      },
    });
  });

  app.get(`${API_PREFIX}/health`, async (_req, res) => {
    const db = getDatabaseHealth();
    const reachable = db.status === 'up' ? await pingDatabase() : false;
    const healthy = db.status === 'up' && reachable;
    res.status(healthy ? 200 : 503).json({
      success: healthy,
      data: {
        status: healthy ? 'ok' : 'degraded',
        database: { ...db, reachable },
        timestamp: new Date().toISOString(),
      },
    });
  });

  app.get(`${API_PREFIX}/ready`, async (_req, res) => {
    const { getReadinessSnapshot } = await import('./modules/ops/readiness.service');
    const data = await getReadinessSnapshot();
    const ok = data.status === 'ready' || (env.NODE_ENV !== 'production' && data.status === 'degraded');
    res.status(ok ? 200 : 503).json({ success: ok, data });
  });

  app.use(`${API_PREFIX}/auth`, authRoutes);
  app.use(`${API_PREFIX}/me`, meRoutes);
  app.use(`${API_PREFIX}/admin`, adminRoutes);
  app.use(`${API_PREFIX}/resident`, residentRoutes);
  app.use(`${API_PREFIX}/guard`, guardRoutes);
  app.use(`${API_PREFIX}/webhooks`, webhookRoutes);
  app.use(`${API_PREFIX}/societies`, societyRoutes);
  app.use(`${API_PREFIX}/users`, usersRoutes);

  // swagger-jsdoc depends on yaml@2.0.0-1; skip docs mount if generation fails in constrained envs.
  try {
    const openApiSpec = buildOpenApiSpec();
    app.use('/api/docs', swaggerUi.serve, swaggerUi.setup(openApiSpec, { explorer: true }));
    app.get('/api/docs.json', (_req, res) => {
      res.json(openApiSpec);
    });
  } catch {
    app.get('/api/docs.json', (_req, res) => {
      res.status(503).json({ success: false, error: { code: 'DOCS_UNAVAILABLE', message: 'OpenAPI unavailable' } });
    });
  }

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
