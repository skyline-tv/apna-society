import type { Server } from 'socket.io';
import { getLogger } from '../../../utils/logger';
import { residentVisitorRoom } from '../../visitors/services/visitor-events.service';

export type FacilitySocketEvent =
  | 'facility:booking_approved'
  | 'facility:booking_rejected'
  | 'facility:booking_cancelled';

export interface FacilityBookingEventPayload {
  bookingId: string;
  societyId: string;
  facilityId: string;
  flatId: string;
  bookedByUserId: string;
  status: string;
  bookingDate: string;
  startAt: string;
  endAt: string;
  feePaiseSnapshot: number;
  feePaid: boolean;
}

type Emitter = (
  event: FacilitySocketEvent,
  rooms: string[],
  payload: FacilityBookingEventPayload,
) => void;

let ioRef: Server | null = null;
let testEmitter: Emitter | null = null;

export function setFacilitySocketIoServer(io: Server | null): void {
  ioRef = io;
}

export function setFacilityEventEmitterForTests(emitter: Emitter | null): void {
  testEmitter = emitter;
}

export function emitFacilityBookingEvent(
  event: FacilitySocketEvent,
  payload: FacilityBookingEventPayload,
): void {
  const safe: FacilityBookingEventPayload = {
    bookingId: payload.bookingId,
    societyId: payload.societyId,
    facilityId: payload.facilityId,
    flatId: payload.flatId,
    bookedByUserId: payload.bookedByUserId,
    status: payload.status,
    bookingDate: payload.bookingDate,
    startAt: payload.startAt,
    endAt: payload.endAt,
    feePaiseSnapshot: payload.feePaiseSnapshot,
    feePaid: payload.feePaid,
  };
  const rooms = [residentVisitorRoom(safe.societyId, safe.bookedByUserId)];

  if (testEmitter) testEmitter(event, rooms, safe);
  if (!ioRef) return;
  for (const room of rooms) ioRef.to(room).emit(event, safe);
  getLogger().debug({ event, rooms, bookingId: safe.bookingId }, 'Facility socket event emitted');
}

export function bookingEventPayload(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  facilityId: { toString(): string };
  flatId: { toString(): string };
  bookedByUserId: { toString(): string };
  status: string;
  bookingDate: string;
  startAt: Date;
  endAt: Date;
  feePaiseSnapshot: number;
  feePaid: boolean;
}): FacilityBookingEventPayload {
  return {
    bookingId: String(doc._id),
    societyId: String(doc.societyId),
    facilityId: String(doc.facilityId),
    flatId: String(doc.flatId),
    bookedByUserId: String(doc.bookedByUserId),
    status: doc.status,
    bookingDate: doc.bookingDate,
    startAt: doc.startAt.toISOString(),
    endAt: doc.endAt.toISOString(),
    feePaiseSnapshot: doc.feePaiseSnapshot,
    feePaid: doc.feePaid,
  };
}
