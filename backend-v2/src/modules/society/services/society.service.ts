import { notFound } from '../../../shared/errors/app-error';
import { formatFlatLabel } from '../../../utils/flat-label';
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

/**
 * Guard-safe (and generally public) flat directory.
 * Never includes occupancy, owner/tenant IDs, or resident PII.
 */
export async function listPublicFlats(societyId: string) {
  const [flats, wings] = await Promise.all([
    FlatModel.find({ societyId, isActive: true })
      .select('societyId wingId number floor')
      .sort({ number: 1 })
      .lean(),
    WingModel.find({ societyId }).select('code').lean(),
  ]);
  const wingMap = new Map(wings.map((wing) => [String(wing._id), wing.code]));
  return flats.map((flat) => {
    const wingCode = wingMap.get(String(flat.wingId)) ?? '';
    return {
      id: String(flat._id),
      societyId: String(flat.societyId),
      wingId: String(flat.wingId),
      wingCode,
      number: flat.number,
      floor: flat.floor,
      label: formatFlatLabel(wingCode, flat.number),
    };
  });
}
