import { notFound } from '../../../shared/errors/app-error';
import { FlatModel } from '../models/flat.model';
import { SocietyModel } from '../models/society.model';
import { WingModel } from '../models/wing.model';

export async function getSocietyById(societyId: string) {
  const society = await SocietyModel.findById(societyId).lean();
  if (!society) {
    throw notFound('Society not found');
  }
  return society;
}

export async function listWings(societyId: string) {
  return WingModel.find({ societyId, isActive: true }).sort({ sortOrder: 1 }).lean();
}

export async function listFlats(societyId: string) {
  return FlatModel.find({ societyId, isActive: true }).sort({ number: 1 }).lean();
}
