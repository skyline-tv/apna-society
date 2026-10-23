import { getEnv } from '../../../config/env';
import { getLogger } from '../../../utils/logger';
import { UserModel } from '../../users/models/user.model';
import {
  NotificationModel,
  type NotificationType,
  type PushDeliveryStatus,
} from '../models/notification.model';
import { listActiveTokensForUser, deactivateTokens } from './device-token.service';
import { isResidentPushRole } from './fcm-access';
import { metadataToFcmData } from './safe-metadata';
import { getPushSender, type PushPriority } from './push-sender';

const HIGH_PRIORITY_TYPES = new Set<NotificationType>(['VISITOR_REQUEST']);
const MAX_ATTEMPTS = 5;
const RETRY_BACKOFF_MS = [30_000, 120_000, 300_000, 900_000, 1_800_000];

function channelForType(type: NotificationType, metadata?: Record<string, unknown>): string {
  if (typeof metadata?.channel === 'string' && metadata.channel) return metadata.channel;
  if (type === 'VISITOR_REQUEST' && metadata?.entryMode === 'WALK_IN') {
    return 'incoming_visitor_call';
  }
  if (type === 'BILL_GENERATED' || type === 'BILL_OVERDUE' || type.startsWith('PAYMENT_')) {
    return 'billing';
  }
  if (type.startsWith('PARCEL_') || type.startsWith('VISITOR_')) {
    return 'visitors';
  }
  if (type === 'ANNOUNCEMENT') return 'notices';
  return 'general';
}

function priorityFor(
  type: NotificationType,
  metadata?: Record<string, unknown>,
): PushPriority {
  if (metadata?.priority === 'high') return 'high';
  if (HIGH_PRIORITY_TYPES.has(type) && metadata?.entryMode === 'WALK_IN') return 'high';
  return 'normal';
}

function deepLinkFor(input: {
  type: string;
  relatedEntityType?: string;
  relatedEntityId?: string;
  metadata?: Record<string, unknown>;
}): string | undefined {
  if (typeof input.metadata?.deepLink === 'string') return input.metadata.deepLink;
  const id = input.relatedEntityId;
  if (!id) return undefined;
  switch (input.type) {
    case 'VISITOR_REQUEST':
      return input.metadata?.entryMode === 'WALK_IN'
        ? `apnasociety://visitor-approval/${id}`
        : `apnasociety://visitor/${id}`;
    case 'VISITOR_APPROVED':
    case 'VISITOR_REJECTED':
    case 'VISITOR_ENTERED':
    case 'VISITOR_EXPIRED':
      return `apnasociety://visitor/${id}`;
    case 'BILL_GENERATED':
    case 'BILL_OVERDUE':
      return `apnasociety://bill/${id}`;
    case 'ANNOUNCEMENT':
      return `apnasociety://notice/${id}`;
    case 'PARCEL_AWAITING_HANDOVER':
    case 'PARCEL_RECEIVED':
      return `apnasociety://parcel/${id}`;
    default:
      return undefined;
  }
}

export async function deliverPushForNotification(notificationId: string): Promise<void> {
  const notification = await NotificationModel.findById(notificationId);
  if (!notification) return;
  if (notification.pushStatus === 'SENT' || notification.pushStatus === 'SKIPPED') return;

  const now = new Date();
  const recipient = await UserModel.findById(notification.recipientUserId).select('roles').lean();
  if (!isResidentPushRole(recipient?.roles)) {
    notification.pushStatus = 'SKIPPED';
    notification.pushAttemptCount += 1;
    notification.pushLastAttemptAt = now;
    await notification.save();
    return;
  }

  const sender = getPushSender();
  const tokens = await listActiveTokensForUser(String(notification.recipientUserId));

  if (tokens.length === 0) {
    notification.pushStatus = sender.isConfigured() ? 'SKIPPED' : 'NOT_CONFIGURED';
    notification.pushAttemptCount += 1;
    notification.pushLastAttemptAt = now;
    await notification.save();
    return;
  }

  if (!sender.isConfigured()) {
    notification.pushStatus = 'NOT_CONFIGURED';
    notification.pushAttemptCount += 1;
    notification.pushLastAttemptAt = now;
    await notification.save();
    return;
  }

  const metadata = (notification.metadata ?? {}) as Record<string, unknown>;
  const deepLink = deepLinkFor({
    type: notification.type,
    relatedEntityType: notification.relatedEntityType,
    relatedEntityId: notification.relatedEntityId,
    metadata,
  });
  const data = {
    ...metadataToFcmData(metadata),
    notificationId: String(notification._id),
    type: notification.type,
    relatedEntityType: notification.relatedEntityType ?? '',
    relatedEntityId: notification.relatedEntityId ?? '',
    title: notification.title,
    body: notification.body,
    ...(deepLink ? { deepLink } : {}),
  };
  const androidChannelId = channelForType(notification.type, metadata);
  const incomingCall =
    androidChannelId === 'incoming_visitor_call' ||
    (notification.type === 'VISITOR_REQUEST' && metadata?.entryMode === 'WALK_IN');

  const results = await sender.send(
    tokens.map((row) => ({
      token: row.token,
      title: notification.title,
      body: notification.body,
      data,
      androidChannelId,
      priority: priorityFor(notification.type, metadata),
      collapseKey: notification.idempotencyKey.slice(0, 64),
      androidDataOnly: incomingCall,
      ttlSeconds: incomingCall ? 120 : undefined,
    })),
  );

  const invalid: string[] = [];
  let successCount = 0;
  let retryable = false;
  for (const result of results) {
    if (result.success) {
      successCount += 1;
      continue;
    }
    if (result.errorCode === 'UNREGISTERED' || result.errorCode === 'INVALID_ARGUMENT') {
      invalid.push(result.token);
    } else if (result.errorCode === 'RETRYABLE') {
      retryable = true;
    }
  }

  if (invalid.length > 0) {
    await deactivateTokens(
      invalid,
      invalid.some((_, i) => results.find((r) => r.token === invalid[i])?.errorCode === 'INVALID_ARGUMENT')
        ? 'INVALID_ARGUMENT'
        : 'UNREGISTERED',
    );
  }

  notification.pushAttemptCount += 1;
  notification.pushLastAttemptAt = now;

  let status: PushDeliveryStatus;
  if (successCount === results.length) {
    status = 'SENT';
    notification.pushSentAt = now;
  } else if (successCount > 0) {
    status = 'PARTIAL';
    notification.pushSentAt = now;
  } else if (retryable && notification.pushAttemptCount < MAX_ATTEMPTS) {
    status = 'FAILED';
  } else {
    status = 'FAILED';
  }
  notification.pushStatus = status;
  await notification.save();

  getLogger().info(
    {
      notificationId: String(notification._id),
      type: notification.type,
      recipientUserId: String(notification.recipientUserId),
      tokens: tokens.length,
      successCount,
      invalidTokens: invalid.length,
      pushStatus: status,
    },
    'Push delivery attempt finished',
  );
}

export function enqueuePushDelivery(notificationId: string): void {
  setImmediate(() => {
    void deliverPushForNotification(notificationId).catch((error) => {
      getLogger().error(
        { err: error, notificationId },
        'Push delivery failed unexpectedly',
      );
    });
  });
}

export async function runPushRetryPass(now = new Date()): Promise<{ retried: number }> {
  const env = getEnv();
  if (!env.FCM_ENABLED && env.NODE_ENV !== 'test') {
    return { retried: 0 };
  }

  const due = await NotificationModel.find({
    pushStatus: 'FAILED',
    pushAttemptCount: { $gt: 0, $lt: MAX_ATTEMPTS },
  })
    .select('_id pushAttemptCount pushLastAttemptAt')
    .limit(100)
    .lean();

  let retried = 0;
  for (const row of due) {
    const attempt = Math.max(1, row.pushAttemptCount);
    const backoff = RETRY_BACKOFF_MS[Math.min(attempt, RETRY_BACKOFF_MS.length) - 1] ?? 30_000;
    const last = row.pushLastAttemptAt ? new Date(row.pushLastAttemptAt).getTime() : 0;
    if (now.getTime() - last < backoff) continue;
    await deliverPushForNotification(String(row._id));
    retried += 1;
  }
  return { retried };
}

let retryTimer: NodeJS.Timeout | undefined;

export function startPushRetryWorker(): void {
  const env = getEnv();
  if (!env.PUSH_RETRY_WORKER_ENABLED) return;
  if (retryTimer) return;
  const tick = () => {
    void runPushRetryPass().catch((error) => {
      getLogger().error({ err: error }, 'Push retry worker pass failed');
    });
  };
  tick();
  retryTimer = setInterval(tick, env.PUSH_RETRY_WORKER_INTERVAL_MS);
  retryTimer.unref?.();
}

export function stopPushRetryWorker(): void {
  if (retryTimer) {
    clearInterval(retryTimer);
    retryTimer = undefined;
  }
}
