import type { Server } from 'socket.io';
import { getLogger } from '../../../utils/logger';
import { residentVisitorRoom } from '../../visitors/services/visitor-events.service';

export type AnnouncementSocketEvent = 'announcement:published';

export interface AnnouncementEventPayload {
  announcementId: string;
  societyId: string;
  title: string;
  category: string;
  priority: string;
  publishedAt: string;
}

type Emitter = (
  event: AnnouncementSocketEvent,
  rooms: string[],
  payload: AnnouncementEventPayload,
) => void;

let ioRef: Server | null = null;
let testEmitter: Emitter | null = null;

export function setAnnouncementSocketIoServer(io: Server | null): void {
  ioRef = io;
}

export function setAnnouncementEventEmitterForTests(emitter: Emitter | null): void {
  testEmitter = emitter;
}

export function emitAnnouncementPublished(
  payload: AnnouncementEventPayload,
  recipientUserIds: string[],
): void {
  const safe: AnnouncementEventPayload = {
    announcementId: payload.announcementId,
    societyId: payload.societyId,
    title: payload.title,
    category: payload.category,
    priority: payload.priority,
    publishedAt: payload.publishedAt,
  };
  const rooms = recipientUserIds.map((uid) => residentVisitorRoom(safe.societyId, uid));
  if (testEmitter) testEmitter('announcement:published', rooms, safe);
  if (!ioRef) return;
  for (const room of rooms) ioRef.to(room).emit('announcement:published', safe);
  getLogger().debug(
    { announcementId: safe.announcementId, recipients: recipientUserIds.length },
    'Announcement socket event emitted',
  );
}
