import type { Request, Response } from 'express';
import {
  attendanceSummary,
  checkOutAttendance,
  correctAttendance,
  listAttendance,
  markAttendance,
} from '../services/attendance.service';
import {
  cancelFutureShift,
  createShift,
  getShift,
  listShifts,
  scheduleView,
  updateFutureShift,
} from '../services/shift.service';
import {
  createStaff,
  deactivateStaff,
  getStaff,
  listStaff,
  reactivateStaff,
  terminateStaff,
  updateStaff,
} from '../services/staff.service';

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

export async function createStaffHandler(req: Request, res: Response) {
  const data = await createStaff(society(req), req.body, actor(req));
  res.status(201).json({ success: true, data });
}
export async function listStaffHandler(req: Request, res: Response) {
  const data = await listStaff(society(req), req.query as never);
  res.json({ success: true, data });
}
export async function getStaffHandler(req: Request, res: Response) {
  const data = await getStaff(society(req), String(req.params.staffId));
  res.json({ success: true, data });
}
export async function updateStaffHandler(req: Request, res: Response) {
  const data = await updateStaff(society(req), String(req.params.staffId), req.body, actor(req));
  res.json({ success: true, data });
}
export async function deactivateStaffHandler(req: Request, res: Response) {
  const data = await deactivateStaff(
    society(req),
    String(req.params.staffId),
    (req.body as { reason?: string }).reason,
    actor(req),
  );
  res.json({ success: true, data });
}
export async function terminateStaffHandler(req: Request, res: Response) {
  const data = await terminateStaff(
    society(req),
    String(req.params.staffId),
    (req.body as { reason?: string }).reason,
    actor(req),
  );
  res.json({ success: true, data });
}
export async function reactivateStaffHandler(req: Request, res: Response) {
  const data = await reactivateStaff(society(req), String(req.params.staffId), actor(req));
  res.json({ success: true, data });
}

export async function markAttendanceHandler(req: Request, res: Response) {
  const data = await markAttendance(society(req), req.body, actor(req));
  res.status(201).json({ success: true, data });
}
export async function checkOutAttendanceHandler(req: Request, res: Response) {
  const data = await checkOutAttendance(
    society(req),
    String(req.params.attendanceId),
    actor(req),
  );
  res.json({ success: true, data });
}
export async function correctAttendanceHandler(req: Request, res: Response) {
  const data = await correctAttendance(
    society(req),
    String(req.params.attendanceId),
    req.body,
    actor(req),
  );
  res.json({ success: true, data });
}
export async function listAttendanceHandler(req: Request, res: Response) {
  const data = await listAttendance(society(req), req.query as never);
  res.json({ success: true, data });
}
export async function attendanceSummaryHandler(req: Request, res: Response) {
  const data = await attendanceSummary(society(req), {
    from: req.query.from as string | undefined,
    to: req.query.to as string | undefined,
  });
  res.json({ success: true, data });
}

export async function createShiftHandler(req: Request, res: Response) {
  const data = await createShift(society(req), req.body, actor(req));
  res.status(201).json({ success: true, data });
}
export async function listShiftsHandler(req: Request, res: Response) {
  const data = await listShifts(society(req), req.query as never);
  res.json({ success: true, data });
}
export async function getShiftHandler(req: Request, res: Response) {
  const data = await getShift(society(req), String(req.params.shiftId));
  res.json({ success: true, data });
}
export async function updateShiftHandler(req: Request, res: Response) {
  const data = await updateFutureShift(
    society(req),
    String(req.params.shiftId),
    req.body,
    actor(req),
  );
  res.json({ success: true, data });
}
export async function cancelShiftHandler(req: Request, res: Response) {
  const data = await cancelFutureShift(
    society(req),
    String(req.params.shiftId),
    (req.body as { reason?: string }).reason,
    actor(req),
  );
  res.json({ success: true, data });
}
export async function scheduleHandler(req: Request, res: Response) {
  const data = await scheduleView(society(req), {
    from: String(req.query.from),
    to: String(req.query.to),
  });
  res.json({ success: true, data });
}
