import type { Server } from 'socket.io';
import { getLogger } from '../../../utils/logger';

export type VisitorSocketEvent =
  | 'visitor:approval_requested'
  | 'visitor:approved'
  | 'visitor:rejected'
  | 'visitor:entered'
  | 'visitor:exited'
  | 'visitor:expired'
  | 'visitor:parcel_authorized'
  | 'parcel:received';

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
  entryMode?: string;
  assignedResidentUserId?: string;
  parcelId?: string;
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
  options?: { includeGuards?: boolean; extraResidentUserIds?: string[] },
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
    entryMode: payload.entryMode,
    assignedResidentUserId: payload.assignedResidentUserId,
    parcelId: payload.parcelId,
  };

  const residentUserIds = [
    ...new Set(
      [
        safe.assignedResidentUserId,
        ...(options?.extraResidentUserIds ?? []),
      ].filter((id): id is string => Boolean(id)),
    ),
  ];
  const residentRooms = residentUserIds.map((id) => residentVisitorRoom(safe.societyId, id));
  const rooms = [
    ...residentRooms,
    ...(options?.includeGuards !== false ? [societyGuardsRoom(safe.societyId)] : []),
  ];
  const guardSafe: VisitorEventPayload = {
    ...safe,
    assignedResidentUserId: undefined,
  };

  if (testEmitter) {
    testEmitter(event, rooms, safe);
  }

  if (!ioRef) {
    return;
  }

  for (const room of residentRooms) {
    ioRef.to(room).emit(event, safe);
  }
  if (options?.includeGuards !== false) {
    ioRef.to(societyGuardsRoom(safe.societyId)).emit(event, guardSafe);
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
  entryMode?: string;
  assignedResidentUserId: { toString(): string };
  parcelId?: string;
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
    entryMode: doc.entryMode,
    assignedResidentUserId: String(doc.assignedResidentUserId),
    parcelId: doc.parcelId,
  };
}
