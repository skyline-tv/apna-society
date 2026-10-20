import type { Request, Response } from 'express';
import {
  approveBooking,
  cancelAdminBooking,
  cancelResidentBooking,
  createBooking,
  getAdminBooking,
  getFacilityAvailability,
  getResidentBooking,
  listAdminBookings,
  listResidentBookings,
  rejectBooking,
} from '../services/booking.service';
import {
  createFacility,
  facilityBookingSummary,
  getFacility,
  listFacilities,
  setFacilityActive,
  updateFacility,
} from '../services/facility.service';

function actor(req: Request) {
  return {
    userId: req.user!.id,
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? undefined,
  };
}
function society(req: Request) {
  return String(req.societyId);
}

export async function adminCreateFacilityHandler(req: Request, res: Response) {
  const data = await createFacility(society(req), req.body, actor(req));
  res.status(201).json({ success: true, data });
}
export async function adminListFacilitiesHandler(req: Request, res: Response) {
  const data = await listFacilities(society(req), req.query as never, { includeAdmin: true });
  res.json({ success: true, data });
}
export async function adminGetFacilityHandler(req: Request, res: Response) {
  const data = await getFacility(society(req), String(req.params.facilityId), {
    includeAdmin: true,
  });
  res.json({ success: true, data });
}
export async function adminUpdateFacilityHandler(req: Request, res: Response) {
  const data = await updateFacility(
    society(req),
    String(req.params.facilityId),
    req.body,
    actor(req),
  );
  res.json({ success: true, data });
}
export async function adminSetFacilityActiveHandler(req: Request, res: Response) {
  const data = await setFacilityActive(
    society(req),
    String(req.params.facilityId),
    Boolean((req.body as { isActive: boolean }).isActive),
    actor(req),
  );
  res.json({ success: true, data });
}
export async function adminFacilitySummaryHandler(req: Request, res: Response) {
  const data = await facilityBookingSummary(society(req));
  res.json({ success: true, data });
}
export async function adminListBookingsHandler(req: Request, res: Response) {
  const data = await listAdminBookings(society(req), req.query as never);
  res.json({ success: true, data });
}
export async function adminGetBookingHandler(req: Request, res: Response) {
  const data = await getAdminBooking(society(req), String(req.params.bookingId));
  res.json({ success: true, data });
}
export async function adminApproveBookingHandler(req: Request, res: Response) {
  const data = await approveBooking(
    society(req),
    String(req.params.bookingId),
    (req.body as { adminNotes?: string }).adminNotes,
    actor(req),
  );
  res.json({ success: true, data });
}
export async function adminRejectBookingHandler(req: Request, res: Response) {
  const data = await rejectBooking(
    society(req),
    String(req.params.bookingId),
    (req.body as { reason: string }).reason,
    actor(req),
  );
  res.json({ success: true, data });
}
export async function adminCancelBookingHandler(req: Request, res: Response) {
  const data = await cancelAdminBooking(
    society(req),
    String(req.params.bookingId),
    (req.body as { reason?: string }).reason,
    actor(req),
  );
  res.json({ success: true, data });
}

export async function residentListFacilitiesHandler(req: Request, res: Response) {
  const data = await listFacilities(society(req), req.query as never);
  res.json({ success: true, data });
}
export async function residentGetFacilityHandler(req: Request, res: Response) {
  const data = await getFacility(society(req), String(req.params.facilityId));
  res.json({ success: true, data });
}
export async function residentAvailabilityHandler(req: Request, res: Response) {
  const data = await getFacilityAvailability(
    society(req),
    String(req.params.facilityId),
    String(req.query.date),
  );
  res.json({ success: true, data });
}
export async function residentCreateBookingHandler(req: Request, res: Response) {
  const data = await createBooking(
    society(req),
    req.user!.id,
    String(req.params.facilityId),
    req.body,
    actor(req),
  );
  res.status(201).json({ success: true, data });
}
export async function residentListBookingsHandler(req: Request, res: Response) {
  const data = await listResidentBookings(society(req), req.user!.id, req.query as never);
  res.json({ success: true, data });
}
export async function residentGetBookingHandler(req: Request, res: Response) {
  const data = await getResidentBooking(
    society(req),
    req.user!.id,
    String(req.params.bookingId),
  );
  res.json({ success: true, data });
}
export async function residentCancelBookingHandler(req: Request, res: Response) {
  const data = await cancelResidentBooking(
    society(req),
    req.user!.id,
    String(req.params.bookingId),
    (req.body as { reason?: string }).reason,
    actor(req),
  );
  res.json({ success: true, data });
}
