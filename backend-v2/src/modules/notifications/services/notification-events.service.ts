import type { Server } from 'socket.io';
import { getLogger } from '../../../utils/logger';
import { residentVisitorRoom } from '../../visitors/services/visitor-events.service';

export type NotificationSocketEvent = 'notification:created';

export interface NotificationSocketPayload {
  id: string;
  societyId: string;
  recipientUserId: string;
  type: string;
  title: string;
  body: string;
  relatedEntityType?: string;
  relatedEntityId?: string;
  isRead: boolean;
  metadata?: Record<string, unknown>;
  createdAt: string;
}

type Emitter = (
  event: NotificationSocketEvent,
  rooms: string[],
  payload: NotificationSocketPayload,
) => void;

let ioRef: Server | null = null;
let testEmitter: Emitter | null = null;

export function setNotificationSocketIoServer(io: Server | null): void {
  ioRef = io;
}

export function setNotificationEventEmitterForTests(emitter: Emitter | null): void {
  testEmitter = emitter;
}

export function emitNotificationCreated(payload: NotificationSocketPayload): void {
  const safe: NotificationSocketPayload = {
    id: payload.id,
    societyId: payload.societyId,
    recipientUserId: payload.recipientUserId,
    type: payload.type,
    title: payload.title,
    body: payload.body,
    relatedEntityType: payload.relatedEntityType,
    relatedEntityId: payload.relatedEntityId,
    isRead: payload.isRead,
    metadata: payload.metadata,
    createdAt: payload.createdAt,
  };
  const rooms = [residentVisitorRoom(safe.societyId, safe.recipientUserId)];
  if (testEmitter) testEmitter('notification:created', rooms, safe);
  if (!ioRef) return;
  for (const room of rooms) ioRef.to(room).emit('notification:created', safe);
  getLogger().debug({ rooms, id: safe.id }, 'Notification socket event emitted');
}
