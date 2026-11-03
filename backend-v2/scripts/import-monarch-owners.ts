/**
 * Import Monarch Solitaire owner roster onto vacant flats.
 *
 * Intentional model: separate login per flat (username = flat code, e.g. a301, c101).
 * Same person on multiple flats keeps the same display name but gets a distinct login
 * for each flat. Occupancy rules are unchanged — one active owner assignment per user.
 *
 * - Skips rows whose name is ***** (treated as vacant / unknown).
 * - Creates one OWNER account per owned flat.
 * - Parses the first Indian mobile from the mobile/notes cell; leftover text becomes occupancy notes.
 *
 * Usage:
 *   npm run import:monarch-owners -- --confirm
 *   npm run import:monarch-owners -- --confirm --password 'Owner@Monarch1'
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadEnv } from '../src/config/env';
import { connectDatabase, disconnectDatabase } from '../src/database/connection';
import { hashPassword } from '../src/utils/password';
import { normalizeMobileE164 } from '../src/utils/phone';
import { assertValidUsername } from '../src/utils/username';
import { SocietyModel } from '../src/modules/society/models/society.model';
import { FlatModel } from '../src/modules/society/models/flat.model';
import { UserModel } from '../src/modules/users/models/user.model';
import { MembershipModel } from '../src/modules/users/models/membership.model';
import { assignOwner } from '../src/modules/society/services/occupancy-lifecycle.service';

const SOCIETY_CODE = 'MONARCH_SOLITAIRE';
const DEFAULT_PASSWORD = 'Owner@Monarch1';
const EMAIL_DOMAIN = 'owners.monarch.local';

type RosterRow = {
  wing: string;
  flat: string;
  name: string;
  mobile?: string;
};

type ParsedContact = {
  mobileE164?: string;
  phoneDisplay?: string;
  notes?: string;
};

function arg(name: string): string | undefined {
  const idx = process.argv.indexOf(`--${name}`);
  if (idx === -1) return undefined;
  return process.argv[idx + 1];
}

function flatNumber(wing: string, flat: string): string {
  return `${wing.toUpperCase()}-${flat}`;
}

function usernameForFlat(wing: string, flat: string): string {
  return assertValidUsername(`${wing.toLowerCase()}${flat}`);
}

function emailForFlat(wing: string, flat: string): string {
  return `${wing.toLowerCase()}${flat}@${EMAIL_DOMAIN}`;
}

function parseContact(raw?: string): ParsedContact {
  if (!raw) return {};
  const trimmed = raw.trim();
  if (!trimmed || trimmed === '*****') return {};

  const digitsOnly = trimmed.replace(/[^\d]/g, '');
  const indiaMatch = trimmed.match(/(?<!\d)([6-9]\d{9})(?!\d)/);
  if (indiaMatch) {
    const local = indiaMatch[1];
    const remainder = trimmed
      .replace(local, '')
      .replace(/^[\s\-–—:|]+/, '')
      .replace(/[\s\-–—:|]+$/, '')
      .trim();
    try {
      const mobileE164 = normalizeMobileE164(local);
      return {
        mobileE164,
        phoneDisplay: `+${mobileE164}`,
        notes: remainder || undefined,
      };
    } catch {
      return { phoneDisplay: trimmed, notes: remainder || undefined };
    }
  }

  // e.g. "97 1556120808" → UAE-style digits; keep as display phone only
  if (digitsOnly.length >= 10 && digitsOnly.length <= 15) {
    return { phoneDisplay: `+${digitsOnly}`, notes: trimmed };
  }

  return { notes: trimmed };
}

function loadRoster(): RosterRow[] {
  const path = resolve(__dirname, 'data/monarch-owners.json');
  return JSON.parse(readFileSync(path, 'utf8')) as RosterRow[];
}

async function main(): Promise<void> {
  if (!process.argv.includes('--confirm')) {
    throw new Error('Refusing to run. Pass --confirm to import Monarch owners.');
  }

  loadEnv();
  await connectDatabase();

  const password = arg('password') ?? DEFAULT_PASSWORD;
  const passwordHash = await hashPassword(password);
  const roster = loadRoster();

  const society = await SocietyModel.findOne({ code: SOCIETY_CODE });
  if (!society) {
    throw new Error(`Society ${SOCIETY_CODE} not found. Run npm run seed first.`);
  }
  const societyId = String(society._id);

  const admin = await UserModel.findOne({ roles: 'ADMIN', isActive: true }).select('_id').lean();
  if (!admin) {
    throw new Error('No admin user found. Run reset:launch or prepare:admin first.');
  }
  const actor = { userId: String(admin._id) };

  const usedMobiles = new Set<string>();
  const existingMobiles = await UserModel.find({ mobileE164: { $exists: true, $ne: null } })
    .select('mobileE164')
    .lean();
  for (const row of existingMobiles) {
    if (row.mobileE164) usedMobiles.add(row.mobileE164);
  }

  const summary = {
    totalRows: roster.length,
    skippedVacant: 0,
    skippedOccupied: 0,
    created: 0,
    reusedUsers: 0,
    assigned: 0,
    errors: [] as Array<{ flat: string; error: string }>,
    credentials: [] as Array<{
      flat: string;
      name: string;
      username: string;
      email: string;
      password: string;
      mobile?: string;
    }>,
  };

  for (const row of roster) {
    const name = row.name?.trim() ?? '';
    const number = flatNumber(row.wing, row.flat);

    if (!name || name === '*****') {
      summary.skippedVacant += 1;
      continue;
    }

    const flat = await FlatModel.findOne({ societyId: society._id, number });
    if (!flat) {
      summary.errors.push({ flat: number, error: 'Flat not found' });
      continue;
    }
    if (flat.occupancyStatus !== 'VACANT' || flat.activeOwnerUserId) {
      summary.skippedOccupied += 1;
      continue;
    }

    const contact = parseContact(row.mobile);
    const username = usernameForFlat(row.wing, row.flat);
    const email = emailForFlat(row.wing, row.flat);

    try {
      let user = await UserModel.findOne({ email }).select('+passwordHash');
      let created = false;

      if (!user) {
        const mobileE164 =
          contact.mobileE164 && !usedMobiles.has(contact.mobileE164)
            ? contact.mobileE164
            : undefined;
        if (mobileE164) usedMobiles.add(mobileE164);

        user = await UserModel.create({
          email,
          username,
          passwordHash,
          mustChangePassword: true,
          passwordChangedAt: new Date(),
          name,
          phone: contact.phoneDisplay,
          ...(mobileE164
            ? {
                mobileE164,
                mobileVerifiedAt: new Date(),
              }
            : {}),
          roles: ['OWNER'],
          isActive: true,
          canLogin: true,
          primarySocietyId: society._id,
          provisionedBy: admin._id,
        });
        created = true;
        summary.created += 1;
      } else {
        summary.reusedUsers += 1;
        if (!user.roles.includes('OWNER')) {
          user.roles = [...user.roles, 'OWNER'];
        }
        user.name = name;
        user.isActive = true;
        user.canLogin = true;
        if (contact.phoneDisplay && !user.phone) user.phone = contact.phoneDisplay;
        if (
          contact.mobileE164 &&
          !user.mobileE164 &&
          !usedMobiles.has(contact.mobileE164)
        ) {
          user.mobileE164 = contact.mobileE164;
          user.mobileVerifiedAt = new Date();
          usedMobiles.add(contact.mobileE164);
        }
        if (!user.passwordHash) {
          user.passwordHash = passwordHash;
          user.mustChangePassword = true;
          user.passwordChangedAt = new Date();
        }
        await user.save();
      }

      const existingMembership = await MembershipModel.findOne({
        societyId: society._id,
        userId: user._id,
        role: 'OWNER',
        isActive: true,
      });
      if (!existingMembership) {
        await MembershipModel.create({
          societyId: society._id,
          userId: user._id,
          role: 'OWNER',
          flatId: null,
          wingId: null,
          isActive: true,
          startsAt: new Date(),
        });
      }

      await assignOwner(
        societyId,
        String(flat._id),
        {
          userId: String(user._id),
          effectiveFrom: new Date(),
          notes: contact.notes,
        },
        actor,
      );

      summary.assigned += 1;
      if (created) {
        summary.credentials.push({
          flat: number,
          name,
          username,
          email,
          password,
          mobile: contact.phoneDisplay,
        });
      }
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
      summary.errors.push({ flat: number, error: message });
    }
  }

  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  await disconnectDatabase();
}

main().catch(async (error: unknown) => {
  console.error(error);
  await disconnectDatabase().catch(() => undefined);
  process.exit(1);
});
