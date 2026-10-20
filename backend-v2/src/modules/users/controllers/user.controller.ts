import type { Request, Response } from 'express';
import { listUsers } from '../services/user.service';

export async function listUsersHandler(_req: Request, res: Response): Promise<void> {
  const users = await listUsers();
  res.json({ success: true, data: users });
}
