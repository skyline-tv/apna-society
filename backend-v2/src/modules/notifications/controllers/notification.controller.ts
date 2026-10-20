import type { Request, Response } from 'express';
import {
  getNotification,
  listNotifications,
  markAllNotificationsRead,
  markNotificationRead,
  unreadNotificationCount,
} from '../services/notification.service';

function societyId(req: Request): string {
  return String(req.societyId);
}

export async function residentListNotificationsHandler(req: Request, res: Response): Promise<void> {
  const data = await listNotifications(societyId(req), req.user!.id, req.query as never);
  res.json({ success: true, data });
}

export async function residentUnreadNotificationCountHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await unreadNotificationCount(societyId(req), req.user!.id);
  res.json({ success: true, data });
}

export async function residentGetNotificationHandler(req: Request, res: Response): Promise<void> {
  const data = await getNotification(
    societyId(req),
    req.user!.id,
    String(req.params.notificationId),
  );
  res.json({ success: true, data });
}

export async function residentMarkNotificationReadHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await markNotificationRead(
    societyId(req),
    req.user!.id,
    String(req.params.notificationId),
    true,
  );
  res.json({ success: true, data });
}

export async function residentMarkNotificationUnreadHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await markNotificationRead(
    societyId(req),
    req.user!.id,
    String(req.params.notificationId),
    false,
  );
  res.json({ success: true, data });
}

export async function residentMarkAllNotificationsReadHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await markAllNotificationsRead(societyId(req), req.user!.id);
  res.json({ success: true, data });
}
