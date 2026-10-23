import { parseObjectId } from '../../../utils/object-id';
import { DeviceTokenModel, type DevicePlatform } from '../models/device-token.model';

export function serializeDeviceToken(doc: {
  _id: { toString(): string };
  userId: { toString(): string };
  societyId: { toString(): string };
  platform: string;
  deviceId?: string;
  isActive: boolean;
  lastSeenAt: Date;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: String(doc._id),
    userId: String(doc.userId),
    societyId: String(doc.societyId),
    platform: doc.platform,
    deviceId: doc.deviceId,
    isActive: doc.isActive,
    lastSeenAt: new Date(doc.lastSeenAt).toISOString(),
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

export async function registerDeviceToken(input: {
  userId: string;
  societyId: string;
  token: string;
  platform: DevicePlatform;
  deviceId?: string;
}) {
  const now = new Date();
  const userId = parseObjectId(input.userId, 'userId');
  if (input.deviceId) {
    await DeviceTokenModel.updateMany(
      {
        userId,
        deviceId: input.deviceId,
        token: { $ne: input.token },
        isActive: true,
      },
      {
        $set: {
          isActive: false,
          deactivatedAt: now,
          deactivationReason: 'TOKEN_REFRESH',
        },
      },
    );
  }
  const doc = await DeviceTokenModel.findOneAndUpdate(
    { token: input.token },
    {
      $set: {
        userId,
        societyId: parseObjectId(input.societyId, 'societyId'),
        token: input.token,
        platform: input.platform,
        deviceId: input.deviceId,
        isActive: true,
        lastSeenAt: now,
      },
      $unset: { deactivatedAt: 1, deactivationReason: 1 },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true },
  );
  return serializeDeviceToken(doc);
}

export async function unregisterDeviceToken(input: {
  userId: string;
  token: string;
}) {
  const doc = await DeviceTokenModel.findOneAndUpdate(
    {
      token: input.token,
      userId: parseObjectId(input.userId, 'userId'),
    },
    {
      $set: {
        isActive: false,
        deactivatedAt: new Date(),
        deactivationReason: 'USER_UNREGISTERED',
      },
    },
    { new: true },
  );
  if (!doc) {
    return { unregistered: false };
  }
  return { unregistered: true };
}

export async function listActiveTokensForUser(userId: string) {
  return DeviceTokenModel.find({
    userId: parseObjectId(userId, 'userId'),
    isActive: true,
  })
    .select('token platform deviceId')
    .lean();
}

export async function deactivateAllTokensForUser(userId: string): Promise<number> {
  const result = await DeviceTokenModel.updateMany(
    { userId: parseObjectId(userId, 'userId'), isActive: true },
    {
      $set: {
        isActive: false,
        deactivatedAt: new Date(),
        deactivationReason: 'LOGOUT',
      },
    },
  );
  return result.modifiedCount;
}

export async function deactivateTokens(
  tokens: string[],
  reason: 'UNREGISTERED' | 'INVALID_ARGUMENT' | 'USER_UNREGISTERED' | 'TOKEN_REFRESH' | 'LOGOUT',
): Promise<number> {
  if (tokens.length === 0) return 0;
  const result = await DeviceTokenModel.updateMany(
    { token: { $in: tokens }, isActive: true },
    {
      $set: {
        isActive: false,
        deactivatedAt: new Date(),
        deactivationReason: reason,
      },
    },
  );
  return result.modifiedCount;
}
