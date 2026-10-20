/**
 * Safe, idempotent migration for existing OTP-era users.
 *
 * - Assigns unique usernames derived from email local-parts when missing.
 * - Does NOT set passwords (admin must use password reset / provision).
 * - Does NOT disable accounts or delete data.
 * - Does NOT reset MongoDB.
 *
 * Usage:
 *   npx tsx scripts/migrate-password-auth.ts [--dry-run]
 */
import { loadEnv } from '../src/config/env';
import { connectDatabase, disconnectDatabase } from '../src/database/connection';
import { UserModel } from '../src/modules/users/models/user.model';
import { usernameFromEmail } from '../src/utils/username';

async function uniqueUsername(base: string, excludeId?: string): Promise<string> {
  let candidate = base.slice(0, 32);
  let n = 0;
  for (;;) {
    const existing = await UserModel.findOne({
      username: candidate,
      ...(excludeId ? { _id: { $ne: excludeId } } : {}),
    })
      .select('_id')
      .lean();
    if (!existing) return candidate;
    n += 1;
    const suffix = `_${n}`;
    candidate = `${base.slice(0, Math.max(3, 32 - suffix.length))}${suffix}`;
  }
}

async function main(): Promise<void> {
  loadEnv();
  const dryRun = process.argv.includes('--dry-run');
  await connectDatabase();

  const users = await UserModel.find({
    $or: [{ username: { $exists: false } }, { username: null }, { username: '' }],
  }).select('_id email username mustChangePassword');

  console.log(`Found ${users.length} user(s) without username.`);

  let updated = 0;
  for (const user of users) {
    const base = usernameFromEmail(user.email);
    const username = await uniqueUsername(base, String(user._id));
    console.log(`  ${user.email} -> ${username}`);
    if (!dryRun) {
      user.username = username;
      // Leave password unset; force change once admin issues credentials.
      if (user.mustChangePassword === undefined) {
        user.mustChangePassword = true;
      }
      await user.save();
    }
    updated += 1;
  }

  console.log(
    dryRun
      ? `Dry run complete. Would update ${updated} user(s).`
      : `Updated ${updated} user(s). Next: admin sets passwords via POST /admin/users/:id/password`,
  );

  await disconnectDatabase();
}

main().catch(async (err) => {
  console.error(err);
  try {
    await disconnectDatabase();
  } catch {
    /* ignore */
  }
  process.exit(1);
});
