import type { Request, Response } from 'express';
import { getSocietyById, listPublicFlats, listWings } from '../services/society.service';

export async function getSocietyHandler(req: Request, res: Response): Promise<void> {
  const society = await getSocietyById(String(req.params.societyId));
  res.json({ success: true, data: society });
}

export async function listWingsHandler(req: Request, res: Response): Promise<void> {
  const wings = await listWings(String(req.params.societyId));
  res.json({ success: true, data: wings });
}

export async function listFlatsHandler(req: Request, res: Response): Promise<void> {
  const flats = await listPublicFlats(String(req.params.societyId));
  res.json({ success: true, data: flats });
}
