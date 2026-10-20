/**
 * Verifies key query plans with explain("executionStats").
 * Run against local/staging Mongo only:
 *   npx tsx scripts/verify-indexes.ts
 */
import mongoose from 'mongoose';
import { loadEnv } from '../src/config/env';

async function explainFind(
  collection: string,
  filter: Record<string, unknown>,
  sort?: Record<string, 1 | -1>,
) {
  const col = mongoose.connection.collection(collection);
  let cursor = col.find(filter);
  if (sort) cursor = cursor.sort(sort);
  const plan = await cursor.explain('executionStats');
  const stats = plan as {
    executionStats?: {
      executionTimeMillis?: number;
      totalDocsExamined?: number;
      nReturned?: number;
      executionStages?: { stage?: string; indexName?: string };
    };
    queryPlanner?: { winningPlan?: { stage?: string; inputStage?: { indexName?: string } } };
  };
  const es = stats.executionStats;
  const stage = es?.executionStages?.stage;
  const indexName =
    es?.executionStages?.indexName ||
    stats.queryPlanner?.winningPlan?.inputStage?.indexName ||
    null;
  return {
    collection,
    filter,
    sort: sort ?? null,
    executionTimeMillis: es?.executionTimeMillis ?? null,
    docsExamined: es?.totalDocsExamined ?? null,
    docsReturned: es?.nReturned ?? null,
    stage: stage ?? null,
    indexName,
    collectionScan: stage === 'COLLSCAN' || String(JSON.stringify(plan)).includes('COLLSCAN'),
  };
}

async function main() {
  const env = loadEnv();
  if (env.NODE_ENV === 'production') {
    console.error('Refusing to run against NODE_ENV=production');
    process.exit(1);
  }

  await mongoose.connect(env.MONGODB_URI);
  const societyId = new mongoose.Types.ObjectId();

  const results = [];
  results.push(
    await explainFind('bills', { societyId, status: { $ne: 'CANCELLED' } }, { billingPeriodStart: -1 }),
  );
  results.push(
    await explainFind(
      'bills',
      { societyId, wingCodeSnapshot: 'A', billingPeriodStart: { $gte: new Date('2020-01-01') } },
      { billingPeriodStart: -1 },
    ),
  );
  results.push(await explainFind('payments', { societyId }, { createdAt: -1 }));
  results.push(
    await explainFind('announcements', { societyId, status: 'PUBLISHED' }, { publishedAt: -1 }),
  );
  results.push(await explainFind('visitorlogs', { societyId }, { entryAt: -1 }));
  results.push(await explainFind('complaints', { societyId }, { createdAt: -1 }));
  results.push(await explainFind('flats', { societyId }, { number: 1 }));

  // eslint-disable-next-line no-console -- CLI report output
  console.log(JSON.stringify({ verifiedAt: new Date().toISOString(), results }, null, 2));
  await mongoose.disconnect();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
