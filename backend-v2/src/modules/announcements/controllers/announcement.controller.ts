import type { Request, Response } from 'express';
import {
  addAnnouncementAttachment,
  announcementSummary,
  archiveAnnouncement,
  cancelAnnouncement,
  createDraftAnnouncement,
  getAdminAnnouncement,
  getAnnouncementAttachmentFile,
  getAnnouncementRecipientSummary,
  getResidentAnnouncement,
  listAdminAnnouncements,
  listResidentAnnouncements,
  publishAnnouncement,
  removeAnnouncementAttachment,
  scheduleAnnouncement,
  setAnnouncementReadState,
  unreadAnnouncementCount,
  updateDraftAnnouncement,
} from '../services/announcement.service';
import type {
  CreateAnnouncementInput,
  UpdateAnnouncementInput,
} from '../validators/announcement.validators';

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

export async function adminCreateAnnouncementHandler(req: Request, res: Response): Promise<void> {
  const data = await createDraftAnnouncement(
    societyId(req),
    req.body as CreateAnnouncementInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function adminListAnnouncementsHandler(req: Request, res: Response): Promise<void> {
  const data = await listAdminAnnouncements(societyId(req), req.query as never);
  res.json({ success: true, data });
}

export async function adminAnnouncementSummaryHandler(req: Request, res: Response): Promise<void> {
  const data = await announcementSummary(societyId(req));
  res.json({ success: true, data });
}

export async function adminGetAnnouncementHandler(req: Request, res: Response): Promise<void> {
  const data = await getAdminAnnouncement(societyId(req), String(req.params.announcementId));
  res.json({ success: true, data });
}

export async function adminUpdateAnnouncementHandler(req: Request, res: Response): Promise<void> {
  const data = await updateDraftAnnouncement(
    societyId(req),
    String(req.params.announcementId),
    req.body as UpdateAnnouncementInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function adminPublishAnnouncementHandler(req: Request, res: Response): Promise<void> {
  const data = await publishAnnouncement(
    societyId(req),
    String(req.params.announcementId),
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function adminScheduleAnnouncementHandler(req: Request, res: Response): Promise<void> {
  const data = await scheduleAnnouncement(
    societyId(req),
    String(req.params.announcementId),
    (req.body as { scheduledAt: Date }).scheduledAt,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function adminCancelAnnouncementHandler(req: Request, res: Response): Promise<void> {
  const data = await cancelAnnouncement(
    societyId(req),
    String(req.params.announcementId),
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function adminArchiveAnnouncementHandler(req: Request, res: Response): Promise<void> {
  const data = await archiveAnnouncement(
    societyId(req),
    String(req.params.announcementId),
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function adminRecipientsHandler(req: Request, res: Response): Promise<void> {
  const data = await getAnnouncementRecipientSummary(
    societyId(req),
    String(req.params.announcementId),
  );
  res.json({ success: true, data });
}

export async function adminUploadAttachmentHandler(req: Request, res: Response): Promise<void> {
  const data = await addAnnouncementAttachment(
    societyId(req),
    String(req.params.announcementId),
    req.user!.id,
    { buffer: req.file!.buffer, originalname: req.file!.originalname },
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function adminRemoveAttachmentHandler(req: Request, res: Response): Promise<void> {
  const data = await removeAnnouncementAttachment(
    societyId(req),
    String(req.params.announcementId),
    String(req.params.attachmentId),
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function adminDownloadAttachmentHandler(req: Request, res: Response): Promise<void> {
  const file = await getAnnouncementAttachmentFile(
    societyId(req),
    String(req.params.announcementId),
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

export async function residentListAnnouncementsHandler(req: Request, res: Response): Promise<void> {
  const data = await listResidentAnnouncements(
    societyId(req),
    req.user!.id,
    req.query as never,
  );
  res.json({ success: true, data });
}

export async function residentUnreadAnnouncementCountHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await unreadAnnouncementCount(societyId(req), req.user!.id);
  res.json({ success: true, data });
}

export async function residentGetAnnouncementHandler(req: Request, res: Response): Promise<void> {
  const data = await getResidentAnnouncement(
    societyId(req),
    req.user!.id,
    String(req.params.announcementId),
  );
  res.json({ success: true, data });
}

export async function residentMarkAnnouncementReadHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await setAnnouncementReadState(
    societyId(req),
    req.user!.id,
    String(req.params.announcementId),
    true,
  );
  res.json({ success: true, data });
}

export async function residentMarkAnnouncementUnreadHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await setAnnouncementReadState(
    societyId(req),
    req.user!.id,
    String(req.params.announcementId),
    false,
  );
  res.json({ success: true, data });
}

export async function residentDownloadAnnouncementAttachmentHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const file = await getAnnouncementAttachmentFile(
    societyId(req),
    String(req.params.announcementId),
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
