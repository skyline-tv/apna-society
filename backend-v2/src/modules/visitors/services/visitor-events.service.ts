import type { Server } from 'socket.io';
import { getLogger } from '../../../utils/logger';

export type VisitorSocketEvent =
  | 'visitor:approval_requested'
  | 'visitor:approved'
  | 'visitor:rejected'
  | 'visitor:entered'
  | 'visitor:exited';

export interface VisitorEventPayload {
  visitorId: string;
  societyId: string;
  flatId: string;
  flatNumberSnapshot: string;
  wingCodeSnapshot: string;
  visitorName: string;
  visitorType: string;
  approvalStatus: string;
  entryStatus: string;
  assignedResidentUserId: string;
  /** Never include OTP fields. */
}

type Emitter = (
  event: VisitorSocketEvent,
  rooms: string[],
  payload: VisitorEventPayload,
) => void;

let ioRef: Server | null = null;
let testEmitter: Emitter | null = null;

export function setSocketIoServer(io: Server | null): void {
  ioRef = io;
}

export function getSocketIoServer(): Server | null {
  return ioRef;
}

/** Test-only capture hook. */
export function setVisitorEventEmitterForTests(emitter: Emitter | null): void {
  testEmitter = emitter;
}

export function residentVisitorRoom(societyId: string, userId: string): string {
  return `society:${societyId}:resident:${userId}`;
}

export function societyGuardsRoom(societyId: string): string {
  return `society:${societyId}:guards`;
}

export function emitVisitorEvent(
  event: VisitorSocketEvent,
  payload: VisitorEventPayload,
  options?: { includeGuards?: boolean },
): void {
  // Strip any accidental OTP-like keys.
  const safe: VisitorEventPayload = {
    visitorId: payload.visitorId,
    societyId: payload.societyId,
    flatId: payload.flatId,
    flatNumberSnapshot: payload.flatNumberSnapshot,
    wingCodeSnapshot: payload.wingCodeSnapshot,
    visitorName: payload.visitorName,
    visitorType: payload.visitorType,
    approvalStatus: payload.approvalStatus,
    entryStatus: payload.entryStatus,
    assignedResidentUserId: payload.assignedResidentUserId,
  };

  const rooms = [residentVisitorRoom(safe.societyId, safe.assignedResidentUserId)];
  if (options?.includeGuards !== false) {
    rooms.push(societyGuardsRoom(safe.societyId));
  }

  if (testEmitter) {
    testEmitter(event, rooms, safe);
  }

  if (!ioRef) {
    return;
  }

  for (const room of rooms) {
    ioRef.to(room).emit(event, safe);
  }
  getLogger().debug({ event, rooms, visitorId: safe.visitorId }, 'Visitor socket event emitted');
}

export function visitorEventPayloadFromDoc(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  flatId: { toString(): string };
  flatNumberSnapshot: string;
  wingCodeSnapshot: string;
  visitorName: string;
  visitorType: string;
  approvalStatus: string;
  entryStatus: string;
  assignedResidentUserId: { toString(): string };
}): VisitorEventPayload {
  return {
    visitorId: String(doc._id),
    societyId: String(doc.societyId),
    flatId: String(doc.flatId),
    flatNumberSnapshot: doc.flatNumberSnapshot,
    wingCodeSnapshot: doc.wingCodeSnapshot,
    visitorName: doc.visitorName,
    visitorType: doc.visitorType,
    approvalStatus: doc.approvalStatus,
    entryStatus: doc.entryStatus,
    assignedResidentUserId: String(doc.assignedResidentUserId),
  };
}
