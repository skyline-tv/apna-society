import { readFileSync } from 'node:fs';
import { getEnv } from '../../../config/env';
import { getLogger } from '../../../utils/logger';

export type PushPriority = 'normal' | 'high';

export interface PushMessage {
  token: string;
  title: string;
  body: string;
  data: Record<string, string>;
  androidChannelId?: string;
  priority?: PushPriority;
  collapseKey?: string;
}

export type PushErrorCode =
  | 'UNREGISTERED'
  | 'INVALID_ARGUMENT'
  | 'RETRYABLE'
  | 'UNKNOWN';

export interface PushSendResult {
  token: string;
  success: boolean;
  messageId?: string;
  errorCode?: PushErrorCode;
}

export interface PushSender {
  isConfigured(): boolean;
  send(messages: PushMessage[]): Promise<PushSendResult[]>;
}

const captured: PushMessage[] = [];

export function getCapturedPushMessages(): PushMessage[] {
  return [...captured];
}

export function clearCapturedPushMessages(): void {
  captured.length = 0;
}

class MemoryPushSender implements PushSender {
  isConfigured(): boolean {
    return true;
  }

  async send(messages: PushMessage[]): Promise<PushSendResult[]> {
    captured.push(...messages);
    return messages.map((message) => ({
      token: message.token,
      success: true,
      messageId: `memory-${message.token.slice(0, 8)}`,
    }));
  }
}

class NoopPushSender implements PushSender {
  isConfigured(): boolean {
    return false;
  }

  async send(messages: PushMessage[]): Promise<PushSendResult[]> {
    return messages.map((message) => ({
      token: message.token,
      success: false,
      errorCode: 'UNKNOWN' as const,
    }));
  }
}

let override: PushSender | null = null;
let firebaseSender: PushSender | null = null;
let firebaseInitAttempted = false;

export function setPushSenderForTests(sender: PushSender | null): void {
  override = sender;
}

function classifyFcmError(code?: string): PushErrorCode {
  if (!code) return 'UNKNOWN';
  if (
    code === 'messaging/registration-token-not-registered' ||
    code === 'messaging/unregistered'
  ) {
    return 'UNREGISTERED';
  }
  if (
    code === 'messaging/invalid-registration-token' ||
    code === 'messaging/invalid-argument'
  ) {
    return 'INVALID_ARGUMENT';
  }
  if (
    code === 'messaging/unavailable' ||
    code === 'messaging/internal-error' ||
    code === 'messaging/server-unavailable' ||
    code === 'messaging/third-party-auth-error' ||
    code === 'messaging/quota-exceeded'
  ) {
    return 'RETRYABLE';
  }
  return 'UNKNOWN';
}

class FirebasePushSender implements PushSender {
  constructor(private readonly messaging: {
    sendEach: (messages: unknown[]) => Promise<{
      responses: Array<{
        success: boolean;
        messageId?: string;
        error?: { code?: string };
      }>;
    }>;
  }) {}

  isConfigured(): boolean {
    return true;
  }

  async send(messages: PushMessage[]): Promise<PushSendResult[]> {
    if (messages.length === 0) return [];
    const payload = messages.map((message) => {
      const androidChannelId = message.androidChannelId ?? 'general';
      const high = message.priority === 'high';
      return {
        token: message.token,
        notification: {
          title: message.title,
          body: message.body,
        },
        data: message.data,
        android: {
          priority: high ? 'high' : 'normal',
          collapseKey: message.collapseKey,
          notification: {
            channelId: androidChannelId,
            defaultSound: true,
            defaultVibrateTimings: true,
            priority: high ? 'high' : 'default',
            visibility: high ? 'public' : 'private',
          },
        },
        apns: {
          headers: high
            ? { 'apns-priority': '10' }
            : { 'apns-priority': '5' },
          payload: {
            aps: {
              sound: 'default',
              'content-available': 1,
              'interruption-level': high ? 'time-sensitive' : 'active',
            },
          },
        },
      };
    });

    const response = await this.messaging.sendEach(payload);
    return response.responses.map((item, index) => ({
      token: messages[index]!.token,
      success: item.success,
      messageId: item.messageId,
      errorCode: item.success ? undefined : classifyFcmError(item.error?.code),
    }));
  }
}

/**
 * Load Admin SDK credentials from a file path (preferred) or inline JSON.
 * Returns null when neither is set or the file cannot be read. Never logs secrets.
 */
export function readFirebaseServiceAccount(): unknown | null {
  const env = getEnv();
  try {
    if (env.FIREBASE_SERVICE_ACCOUNT_PATH) {
      const raw = readFileSync(env.FIREBASE_SERVICE_ACCOUNT_PATH, 'utf8');
      return JSON.parse(raw) as unknown;
    }
    if (env.FCM_SERVICE_ACCOUNT_JSON) {
      return JSON.parse(env.FCM_SERVICE_ACCOUNT_JSON) as unknown;
    }
  } catch (error) {
    getLogger().error(
      { err: error instanceof Error ? error.message : 'read failed' },
      'Failed to load Firebase service account; FCM remains disabled',
    );
  }
  return null;
}

function tryInitFirebaseSender(): PushSender | null {
  if (firebaseInitAttempted) return firebaseSender;
  firebaseInitAttempted = true;
  const env = getEnv();
  if (!env.FCM_ENABLED) return null;

  try {
    const serviceAccount = readFirebaseServiceAccount();
    if (!serviceAccount) {
      getLogger().warn(
        'FCM_ENABLED=true but no service account file or JSON was loaded; push delivery disabled',
      );
      return null;
    }
    // Lazy require so tests without the native SDK still boot.
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const admin = require('firebase-admin') as {
      apps: unknown[];
      initializeApp: (options?: unknown) => void;
      credential: { cert: (input: unknown) => unknown };
      messaging: () => FirebasePushSender['messaging'];
    };
    if (!admin.apps.length) {
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    }
    firebaseSender = new FirebasePushSender(admin.messaging());
    getLogger().info(
      {
        credentialSource: env.FIREBASE_SERVICE_ACCOUNT_PATH ? 'file' : 'json',
      },
      'FCM push sender initialized',
    );
    return firebaseSender;
  } catch (error) {
    getLogger().error(
      { err: error instanceof Error ? error.message : 'init failed' },
      'FCM push sender initialization failed; push delivery disabled',
    );
    firebaseSender = null;
    return null;
  }
}

export function getPushSender(): PushSender {
  if (override) return override;
  const env = getEnv();
  if (env.NODE_ENV === 'test') {
    return new MemoryPushSender();
  }
  const firebase = tryInitFirebaseSender();
  if (firebase) return firebase;
  return new NoopPushSender();
}

export function resetPushSenderForTests(): void {
  override = null;
  firebaseSender = null;
  firebaseInitAttempted = false;
  clearCapturedPushMessages();
}
