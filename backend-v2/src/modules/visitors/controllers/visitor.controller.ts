import type { Request, Response } from 'express';
import { getRequestSocietyId } from '../../../middleware/admin-society';
import {
  approveVisitor,
  cancelVisitor,
  checkoutVisitor,
  createVisitorRequest,
  getAdminVisitorSummary,
  getGuardDashboard,
  getVisitor,
  listVisitorsForSociety,
  rejectVisitor,
  confirmVisitorEntry,
  verifyEntryOtp,
  verifyEntryOtpByCode,
} from '../services/visitor.service';
import type { CreateVisitorInput, ListVisitorsQuery } from '../validators/visitor.validators';

function actorFrom(req: Request) {
  return {
    userId: req.user!.id,
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? undefined,
  };
}

function societyId(req: Request): string {
  return String(req.societyId);
}

export async function guardCreateVisitorHandler(req: Request, res: Response): Promise<void> {
  const data = await createVisitorRequest(
    societyId(req),
    req.user!.id,
    req.body as CreateVisitorInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function guardListVisitorsHandler(req: Request, res: Response): Promise<void> {
  const data = await listVisitorsForSociety(societyId(req), {
    ...(req.query as unknown as ListVisitorsQuery),
    forGuard: true,
  });
  res.json({ success: true, data });
}

export async function guardGetVisitorHandler(req: Request, res: Response): Promise<void> {
  const data = await getVisitor(societyId(req), String(req.params.visitorId), {
    forGuard: true,
  });
  res.json({ success: true, data });
}

export async function guardVerifyOtpByCodeHandler(req: Request, res: Response): Promise<void> {
  const data = await verifyEntryOtpByCode(
    societyId(req),
    String((req.body as { otp: string }).otp),
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function guardVerifyOtpHandler(req: Request, res: Response): Promise<void> {
  const data = await verifyEntryOtp(
    societyId(req),
    String(req.params.visitorId),
    String((req.body as { otp: string }).otp),
    req.user!.id,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function guardConfirmEntryHandler(req: Request, res: Response): Promise<void> {
  const data = await confirmVisitorEntry(
    societyId(req),
    String(req.params.visitorId),
    req.user!.id,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function guardCheckoutHandler(req: Request, res: Response): Promise<void> {
  const data = await checkoutVisitor(
    societyId(req),
    String(req.params.visitorId),
    req.user!.id,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function guardDashboardHandler(req: Request, res: Response): Promise<void> {
  const data = await getGuardDashboard(societyId(req));
  res.json({ success: true, data });
}

export async function residentListVisitorsHandler(req: Request, res: Response): Promise<void> {
  const data = await listVisitorsForSociety(societyId(req), {
    ...(req.query as unknown as ListVisitorsQuery),
    assignedResidentUserId: req.user!.id,
  });
  res.json({ success: true, data });
}

export async function residentPendingVisitorsHandler(req: Request, res: Response): Promise<void> {
  const data = await listVisitorsForSociety(societyId(req), {
    assignedResidentUserId: req.user!.id,
    approvalStatus: 'PENDING',
    page: Number(req.query.page ?? 1),
    limit: Number(req.query.limit ?? 20),
  });
  res.json({ success: true, data });
}

export async function residentGetVisitorHandler(req: Request, res: Response): Promise<void> {
  const data = await getVisitor(societyId(req), String(req.params.visitorId), {
    assignedResidentUserId: req.user!.id,
  });
  res.json({ success: true, data });
}

export async function residentApproveHandler(req: Request, res: Response): Promise<void> {
  const data = await approveVisitor(
    societyId(req),
    String(req.params.visitorId),
    req.user!.id,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function residentRejectHandler(req: Request, res: Response): Promise<void> {
  const data = await rejectVisitor(
    societyId(req),
    String(req.params.visitorId),
    req.user!.id,
    (req.body as { reason?: string }).reason,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function residentCancelHandler(req: Request, res: Response): Promise<void> {
  const data = await cancelVisitor(
    societyId(req),
    String(req.params.visitorId),
    req.user!.id,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function adminListVisitorsHandler(req: Request, res: Response): Promise<void> {
  const data = await listVisitorsForSociety(getRequestSocietyId(req), {
    ...(req.query as unknown as ListVisitorsQuery),
  });
  res.json({ success: true, data });
}

export async function adminVisitorSummaryHandler(req: Request, res: Response): Promise<void> {
  const data = await getAdminVisitorSummary(getRequestSocietyId(req));
  res.json({ success: true, data });
}

export async function adminGetVisitorHandler(req: Request, res: Response): Promise<void> {
  const data = await getVisitor(getRequestSocietyId(req), String(req.params.visitorId));
  res.json({ success: true, data });
}
