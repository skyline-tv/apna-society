/**
 * Seeds the isolated Google Play demo database.
 * Refuses to run unless DEMO_MODE=true and DEMO_MONGODB_URI is a non-production database.
 */
import { DEMO_ACCOUNTS, DEMO_MODE_LABEL, DEMO_VISITOR_OTP } from '../src/config/demo';
import { loadEnv } from '../src/config/env';
import { connectDatabase, disconnectDatabase } from '../src/database/connection';
import { seedDemoDataset } from '../src/modules/demo/seed-demo';
import { getLogger, resetLogger } from '../src/utils/logger';

async function main(): Promise<void> {
  loadEnv();
  resetLogger();
  const logger = getLogger();
  await connectDatabase();
  const result = await seedDemoDataset();
  logger.info(
    {
      label: DEMO_MODE_LABEL,
      society: result.societyName,
      societyId: result.societyId,
      created: result.created,
      accounts: result.accounts,
      visitorOtp: DEMO_VISITOR_OTP,
      adminUser: DEMO_ACCOUNTS.admin.username,
    },
    'Demo dataset ready',
  );
  await disconnectDatabase();
}

main().catch(async (error: unknown) => {
  console.error(error);
  await disconnectDatabase().catch(() => undefined);
  process.exit(1);
});
