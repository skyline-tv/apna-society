import type { Request, Response } from 'express';
import {
  addComplaintAttachment,
  assignComplaint,
  cancelAdminComplaint,
  cancelResidentComplaint,
  closeComplaint,
  createComplaint,
  getAdminComplaint,
  getComplaintAttachmentFile,
  getComplaintSummary,
  getResidentComplaint,
  listAdminComplaints,
  listComplaintCategories,
  listResidentComplaints,
  resolveComplaint,
  startComplaint,
  unassignComplaint,
  updateComplaintPriority,
} from '../services/complaint.service';
import type {
  AssignComplaintInput,
  CreateComplaintInput,
  ListComplaintsQuery,
} from '../validators/complaint.validators';

function actorFrom(req: Request, role: string) {
  return {
    userId: req.user!.id,
    role,
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? undefined,
  };
}

function societyId(req: Request): string {
  return String(req.societyId);
}

export async function residentCreateComplaintHandler(req: Request, res: Response): Promise<void> {
  const role = req.user!.roles.includes('TENANT')
    ? 'TENANT'
    : req.user!.roles.includes('OWNER')
      ? 'OWNER'
      : 'ADMIN';
  const data = await createComplaint(
    societyId(req),
    req.user!.id,
    req.body as CreateComplaintInput,
    actorFrom(req, role),
  );
  res.status(201).json({ success: true, data });
}

export async function residentListComplaintsHandler(req: Request, res: Response): Promise<void> {
  const data = await listResidentComplaints(
    societyId(req),
    req.user!.id,
    req.query as unknown as ListComplaintsQuery,
  );
  res.json({ success: true, data });
}

export async function residentGetComplaintHandler(req: Request, res: Response): Promise<void> {
  const data = await getResidentComplaint(
    societyId(req),
    req.user!.id,
    String(req.params.complaintId),
  );
  res.json({ success: true, data });
}

export async function residentCancelComplaintHandler(req: Request, res: Response): Promise<void> {
  const role = req.user!.roles.includes('TENANT') ? 'TENANT' : 'OWNER';
  const data = await cancelResidentComplaint(
    societyId(req),
    req.user!.id,
    String(req.params.complaintId),
    (req.body as { reason?: string }).reason,
    actorFrom(req, role),
  );
  res.json({ success: true, data });
}

export async function residentUploadAttachmentHandler(req: Request, res: Response): Promise<void> {
  const role = req.user!.roles.includes('TENANT') ? 'TENANT' : 'OWNER';
  const data = await addComplaintAttachment(
    societyId(req),
    String(req.params.complaintId),
    req.user!.id,
    { buffer: req.file!.buffer, originalname: req.file!.originalname },
    actorFrom(req, role),
  );
  res.status(201).json({ success: true, data });
}

export async function residentDownloadAttachmentHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const file = await getComplaintAttachmentFile(
    societyId(req),
    String(req.params.complaintId),
    String(req.params.attachmentId),
    req.user!.id,
  );
  res.setHeader('Content-Type', file.mimeType);
  res.setHeader(
    'Content-Disposition',
    `inline; filename="${file.originalFilename.replace(/"/g, '')}"`,
  );
  res.send(file.buffer);
}

export async function adminListComplaintsHandler(req: Request, res: Response): Promise<void> {
  const data = await listAdminComplaints(
    societyId(req),
    req.query as unknown as ListComplaintsQuery,
  );
  res.json({ success: true, data });
}

export async function adminGetComplaintHandler(req: Request, res: Response): Promise<void> {
  const data = await getAdminComplaint(societyId(req), String(req.params.complaintId));
  res.json({ success: true, data });
}

export async function adminSummaryHandler(req: Request, res: Response): Promise<void> {
  const data = await getComplaintSummary(societyId(req), {
    from: req.query.from ? new Date(String(req.query.from)) : undefined,
    to: req.query.to ? new Date(String(req.query.to)) : undefined,
  });
  res.json({ success: true, data });
}

export async function adminCategoriesHandler(_req: Request, res: Response): Promise<void> {
  res.json({ success: true, data: listComplaintCategories() });
}

export async function adminUpdatePriorityHandler(req: Request, res: Response): Promise<void> {
  const data = await updateComplaintPriority(
    societyId(req),
    String(req.params.complaintId),
    (req.body as { priority: 'LOW' | 'MEDIUM' | 'HIGH' | 'URGENT' }).priority,
    actorFrom(req, 'ADMIN'),
  );
  res.json({ success: true, data });
}

export async function adminAssignHandler(req: Request, res: Response): Promise<void> {
  const data = await assignComplaint(
    societyId(req),
    String(req.params.complaintId),
    req.body as AssignComplaintInput,
    actorFrom(req, 'ADMIN'),
  );
  res.json({ success: true, data });
}

export async function adminUnassignHandler(req: Request, res: Response): Promise<void> {
  const data = await unassignComplaint(
    societyId(req),
    String(req.params.complaintId),
    (req.body as { reason?: string }).reason,
    actorFrom(req, 'ADMIN'),
  );
  res.json({ success: true, data });
}

export async function adminStartHandler(req: Request, res: Response): Promise<void> {
  const data = await startComplaint(
    societyId(req),
    String(req.params.complaintId),
    actorFrom(req, 'ADMIN'),
  );
  res.json({ success: true, data });
}

export async function adminResolveHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as { resolutionNotes: string; internalNotes?: string };
  const data = await resolveComplaint(
    societyId(req),
    String(req.params.complaintId),
    body.resolutionNotes,
    body.internalNotes,
    actorFrom(req, 'ADMIN'),
  );
  res.json({ success: true, data });
}

export async function adminCloseHandler(req: Request, res: Response): Promise<void> {
  const data = await closeComplaint(
    societyId(req),
    String(req.params.complaintId),
    actorFrom(req, 'ADMIN'),
  );
  res.json({ success: true, data });
}

export async function adminCancelHandler(req: Request, res: Response): Promise<void> {
  const data = await cancelAdminComplaint(
    societyId(req),
    String(req.params.complaintId),
    (req.body as { reason: string }).reason,
    actorFrom(req, 'ADMIN'),
  );
  res.json({ success: true, data });
}

export async function adminUploadAttachmentHandler(req: Request, res: Response): Promise<void> {
  const data = await addComplaintAttachment(
    societyId(req),
    String(req.params.complaintId),
    req.user!.id,
    { buffer: req.file!.buffer, originalname: req.file!.originalname },
    actorFrom(req, 'ADMIN'),
    { asAdmin: true },
  );
  res.status(201).json({ success: true, data });
}

export async function adminDownloadAttachmentHandler(req: Request, res: Response): Promise<void> {
  const file = await getComplaintAttachmentFile(
    societyId(req),
    String(req.params.complaintId),
    String(req.params.attachmentId),
    req.user!.id,
    { asAdmin: true },
  );
  res.setHeader('Content-Type', file.mimeType);
  res.setHeader(
    'Content-Disposition',
    `inline; filename="${file.originalFilename.replace(/"/g, '')}"`,
  );
  res.send(file.buffer);
}
