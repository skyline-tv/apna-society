import type { Server } from 'socket.io';
import { getLogger } from '../../../utils/logger';
import { residentVisitorRoom } from '../../visitors/services/visitor-events.service';

export type ComplaintSocketEvent =
  | 'complaint:assigned'
  | 'complaint:status_changed'
  | 'complaint:reassigned';

export interface ComplaintEventPayload {
  complaintId: string;
  societyId: string;
  flatId: string;
  complaintNumber: string;
  status: string;
  priority: string;
  category: string;
  title: string;
  raisedByUserId: string;
  assignedToUserId?: string;
  /** Never include internalNotes, phone numbers, or storage keys. */
}

type Emitter = (
  event: ComplaintSocketEvent,
  rooms: string[],
  payload: ComplaintEventPayload,
) => void;

let ioRef: Server | null = null;
let testEmitter: Emitter | null = null;

export function setComplaintSocketIoServer(io: Server | null): void {
  ioRef = io;
}

/** Test-only capture hook. */
export function setComplaintEventEmitterForTests(emitter: Emitter | null): void {
  testEmitter = emitter;
}

export function emitComplaintEvent(
  event: ComplaintSocketEvent,
  payload: ComplaintEventPayload,
  options?: { notifyAssignee?: boolean },
): void {
  const safe: ComplaintEventPayload = {
    complaintId: payload.complaintId,
    societyId: payload.societyId,
    flatId: payload.flatId,
    complaintNumber: payload.complaintNumber,
    status: payload.status,
    priority: payload.priority,
    category: payload.category,
    title: payload.title,
    raisedByUserId: payload.raisedByUserId,
    assignedToUserId: payload.assignedToUserId,
  };

  const rooms = [residentVisitorRoom(safe.societyId, safe.raisedByUserId)];
  if (
    options?.notifyAssignee !== false &&
    safe.assignedToUserId &&
    safe.assignedToUserId !== safe.raisedByUserId
  ) {
    rooms.push(residentVisitorRoom(safe.societyId, safe.assignedToUserId));
  }

  if (testEmitter) {
    testEmitter(event, rooms, safe);
  }

  if (!ioRef) return;

  for (const room of rooms) {
    ioRef.to(room).emit(event, safe);
  }
  getLogger().debug(
    { event, rooms, complaintId: safe.complaintId },
    'Complaint socket event emitted',
  );
}

export function complaintEventPayloadFromDoc(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  flatId: { toString(): string };
  complaintNumber: string;
  status: string;
  priority: string;
  category: string;
  title: string;
  raisedByUserId: { toString(): string };
  assignedToUserId?: { toString(): string };
}): ComplaintEventPayload {
  return {
    complaintId: String(doc._id),
    societyId: String(doc.societyId),
    flatId: String(doc.flatId),
    complaintNumber: doc.complaintNumber,
    status: doc.status,
    priority: doc.priority,
    category: doc.category,
    title: doc.title,
    raisedByUserId: String(doc.raisedByUserId),
    assignedToUserId: doc.assignedToUserId ? String(doc.assignedToUserId) : undefined,
  };
}
