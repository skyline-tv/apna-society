import { notFound } from '../../../shared/errors/app-error';
import { writeAuditLog } from '../../auth/services/audit.service';
import { FlatModel } from '../models/flat.model';
import { SocietyModel } from '../models/society.model';
import { WingModel } from '../models/wing.model';
import type { SocietyConfiguration, SocietySummary } from '../types/society.types';
import type { UpdateSocietyInput } from '../validators/admin.validators';
import { serializeSociety, serializeWing } from './serializers';

export async function getAdminSociety(societyId: string): Promise<SocietySummary> {
  const society = await SocietyModel.findById(societyId).lean();
  if (!society) {
    throw notFound('Society not found');
  }
  return serializeSociety(society);
}

export async function updateAdminSociety(
  societyId: string,
  input: UpdateSocietyInput,
  actor: { userId: string; ipAddress?: string; userAgent?: string },
): Promise<SocietySummary> {
  const society = await SocietyModel.findById(societyId);
  if (!society) {
    throw notFound('Society not found');
  }

  const before = {
    name: society.name,
    address: society.address,
    city: society.city,
    state: society.state,
    pincode: society.pincode,
    contactEmail: society.contactEmail,
    contactPhone: society.contactPhone,
    timezone: society.config.timezone,
    currency: society.config.currency,
    maintenanceDayOfMonth: society.config.maintenanceDayOfMonth,
    isActive: society.isActive,
  };

  if (input.name !== undefined) society.name = input.name;
  if (input.address !== undefined) society.address = input.address;
  if (input.city !== undefined) society.city = input.city;
  if (input.state !== undefined) society.state = input.state;
  if (input.pincode !== undefined) society.pincode = input.pincode;
  if (input.contactEmail !== undefined) society.contactEmail = input.contactEmail;
  if (input.contactPhone !== undefined) society.contactPhone = input.contactPhone;
  if (input.isActive !== undefined) society.isActive = input.isActive;
  if (input.timezone !== undefined) society.config.timezone = input.timezone;
  if (input.currency !== undefined) society.config.currency = input.currency;
  if (input.maintenanceDayOfMonth !== undefined) {
    society.config.maintenanceDayOfMonth = input.maintenanceDayOfMonth;
  }

  // Identifiers (code / _id) are intentionally immutable.
  await society.save();

  await writeAuditLog({
    action: 'SOCIETY_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Society',
    targetId: societyId,
    metadata: { before, after: input },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeSociety(society.toObject());
}

export async function getSocietyConfiguration(societyId: string): Promise<SocietyConfiguration> {
  const society = await SocietyModel.findById(societyId).lean();
  if (!society) {
    throw notFound('Society not found');
  }

  const [wings, flatStats] = await Promise.all([
    WingModel.find({ societyId }).sort({ sortOrder: 1, code: 1 }).lean(),
    FlatModel.aggregate<{
      _id: null;
      flats: number;
      activeFlats: number;
      inactiveFlats: number;
      monthlyMaintenanceTotal: number;
      rate4000Count: number;
      rate5000Count: number;
    }>([
      { $match: { societyId: society._id } },
      {
        $group: {
          _id: null,
          flats: { $sum: 1 },
          activeFlats: { $sum: { $cond: ['$isActive', 1, 0] } },
          inactiveFlats: { $sum: { $cond: ['$isActive', 0, 1] } },
          monthlyMaintenanceTotal: { $sum: '$maintenanceRate' },
          rate4000Count: {
            $sum: { $cond: [{ $eq: ['$maintenanceRate', 4000] }, 1, 0] },
          },
          rate5000Count: {
            $sum: { $cond: [{ $eq: ['$maintenanceRate', 5000] }, 1, 0] },
          },
        },
      },
    ]),
  ]);

  const flatCounts = await FlatModel.aggregate<{ _id: unknown; count: number }>([
    { $match: { societyId: society._id } },
    { $group: { _id: '$wingId', count: { $sum: 1 } } },
  ]);
  const countByWing = new Map(flatCounts.map((row) => [String(row._id), row.count]));
  const stats = flatStats[0];

  return {
    society: serializeSociety(society),
    totals: {
      wings: wings.length,
      flats: stats?.flats ?? 0,
      activeFlats: stats?.activeFlats ?? 0,
      inactiveFlats: stats?.inactiveFlats ?? 0,
      monthlyMaintenanceTotal: stats?.monthlyMaintenanceTotal ?? 0,
      rate4000Count: stats?.rate4000Count ?? 0,
      rate5000Count: stats?.rate5000Count ?? 0,
    },
    wings: wings.map((wing) => ({
      ...serializeWing(wing, countByWing.get(String(wing._id)) ?? 0),
      id: String(wing._id),
      code: wing.code,
      name: wing.name,
      floors: wing.floors,
      flatsPerFloor: wing.flatsPerFloor,
      sortOrder: wing.sortOrder,
      isActive: wing.isActive,
      flatCount: countByWing.get(String(wing._id)) ?? 0,
    })),
  };
}
