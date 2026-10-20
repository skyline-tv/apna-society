import type { Server } from 'socket.io';
import { getLogger } from '../../../utils/logger';
import { residentVisitorRoom } from '../../visitors/services/visitor-events.service';

export type StaffSocketEvent = 'staff:shift_assigned';

export interface StaffShiftEventPayload {
  shiftId: string;
  societyId: string;
  staffId: string;
  linkedUserId: string;
  shiftDate: string;
  startAt: string;
  endAt: string;
  dutyLocation?: string;
}

type Emitter = (event: StaffSocketEvent, rooms: string[], payload: StaffShiftEventPayload) => void;

let ioRef: Server | null = null;
let testEmitter: Emitter | null = null;

export function setStaffSocketIoServer(io: Server | null): void {
  ioRef = io;
}

export function setStaffEventEmitterForTests(emitter: Emitter | null): void {
  testEmitter = emitter;
}

export function emitStaffShiftEvent(
  event: StaffSocketEvent,
  payload: StaffShiftEventPayload,
): void {
  const safe: StaffShiftEventPayload = {
    shiftId: payload.shiftId,
    societyId: payload.societyId,
    staffId: payload.staffId,
    linkedUserId: payload.linkedUserId,
    shiftDate: payload.shiftDate,
    startAt: payload.startAt,
    endAt: payload.endAt,
    dutyLocation: payload.dutyLocation,
  };
  const rooms = [residentVisitorRoom(safe.societyId, safe.linkedUserId)];

  if (testEmitter) testEmitter(event, rooms, safe);
  if (!ioRef) return;
  for (const room of rooms) ioRef.to(room).emit(event, safe);
  getLogger().debug({ event, rooms, shiftId: safe.shiftId }, 'Staff socket event emitted');
}

export function staffShiftPayload(
  doc: {
    _id: { toString(): string };
    societyId: { toString(): string };
    staffId: { toString(): string };
    shiftDate: string;
    startAt: Date;
    endAt: Date;
    dutyLocation?: string;
  },
  linkedUserId: string,
): StaffShiftEventPayload {
  return {
    shiftId: String(doc._id),
    societyId: String(doc.societyId),
    staffId: String(doc.staffId),
    linkedUserId,
    shiftDate: doc.shiftDate,
    startAt: doc.startAt.toISOString(),
    endAt: doc.endAt.toISOString(),
    dutyLocation: doc.dutyLocation,
  };
}
