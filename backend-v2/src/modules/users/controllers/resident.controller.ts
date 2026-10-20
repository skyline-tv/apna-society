import type { Request, Response } from 'express';
import {
  getResidentFlat,
  getResidentFlatOccupancy,
  getResidentProfile,
  listResidentFlats,
} from '../services/resident.service';

export async function residentProfileHandler(req: Request, res: Response): Promise<void> {
  const data = await getResidentProfile(req.user!.id);
  res.json({ success: true, data });
}

export async function residentFlatsHandler(req: Request, res: Response): Promise<void> {
  const data = await listResidentFlats(req.user!.id);
  res.json({ success: true, data });
}

export async function residentFlatHandler(req: Request, res: Response): Promise<void> {
  const data = await getResidentFlat(req.user!.id, String(req.params.flatId));
  res.json({ success: true, data });
}

export async function residentOccupancyHandler(req: Request, res: Response): Promise<void> {
  const data = await getResidentFlatOccupancy(req.user!.id, String(req.params.flatId));
  res.json({ success: true, data });
}
