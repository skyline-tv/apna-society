import type { FlatType, OccupancyStatus } from '../../../config/constants';
import { formatFlatLabel } from '../../../utils/flat-label';
import { DEFAULT_TIMEZONE } from '../../../config/constants';
import type { FlatSummary, ResidentSummary, SocietySummary, WingSummary } from '../types/society.types';

export function serializeSociety(society: {
  _id: { toString(): string };
  name: string;
  code: string;
  address?: string;
  city?: string;
  state?: string;
  pincode?: string;
  contactEmail?: string;
  contactPhone?: string;
  isActive: boolean;
  config?: {
    currency?: string;
    timezone?: string;
    maintenanceDayOfMonth?: number;
    annualInterestRateBps?: number;
  };
  createdAt: Date;
  updatedAt: Date;
}): SocietySummary {
  return {
    id: String(society._id),
    name: society.name,
    code: society.code,
    address: society.address,
    city: society.city,
    state: society.state,
    pincode: society.pincode,
    contactEmail: society.contactEmail,
    contactPhone: society.contactPhone,
    timezone: society.config?.timezone ?? DEFAULT_TIMEZONE,
    currency: society.config?.currency ?? 'INR',
    maintenanceDayOfMonth: society.config?.maintenanceDayOfMonth ?? 1,
    annualInterestRateBps: society.config?.annualInterestRateBps ?? 2400,
    isActive: society.isActive,
    createdAt: new Date(society.createdAt).toISOString(),
    updatedAt: new Date(society.updatedAt).toISOString(),
  };
}

export function serializeWing(
  wing: {
    _id: { toString(): string };
    societyId: { toString(): string };
    name: string;
    code: string;
    floors: number;
    flatsPerFloor: number;
    sortOrder: number;
    isActive: boolean;
    createdAt: Date;
    updatedAt: Date;
  },
  flatCount = 0,
): WingSummary {
  return {
    id: String(wing._id),
    societyId: String(wing.societyId),
    name: wing.name,
    code: wing.code,
    floors: wing.floors,
    flatsPerFloor: wing.flatsPerFloor,
    sortOrder: wing.sortOrder,
    isActive: wing.isActive,
    flatCount,
    createdAt: new Date(wing.createdAt).toISOString(),
    updatedAt: new Date(wing.updatedAt).toISOString(),
  };
}

export function serializeFlat(
  flat: {
    _id: { toString(): string };
    societyId: { toString(): string };
    wingId: { toString(): string };
    number: string;
    floor: number;
    position: number;
    flatType: FlatType;
    maintenanceRate: number;
    isActive: boolean;
    occupancyStatus: OccupancyStatus;
    parking?: { hasParking?: boolean; slotLabel?: string };
    notes?: string;
    createdAt: Date;
    updatedAt: Date;
  },
  extras: {
    wingCode?: string;
    wingName?: string;
    activeOwner?: ResidentSummary;
    activeTenant?: ResidentSummary;
  } = {},
): FlatSummary {
  return {
    id: String(flat._id),
    societyId: String(flat.societyId),
    wingId: String(flat.wingId),
    wingCode: extras.wingCode,
    wingName: extras.wingName,
    number: flat.number,
    label: formatFlatLabel(extras.wingCode, flat.number),
    floor: flat.floor,
    position: flat.position,
    flatType: flat.flatType,
    maintenanceRate: flat.maintenanceRate,
    isActive: flat.isActive,
    occupancyStatus: flat.occupancyStatus,
    parking: flat.parking
      ? {
          hasParking: Boolean(flat.parking.hasParking),
          slotLabel: flat.parking.slotLabel,
        }
      : undefined,
    notes: flat.notes,
    activeOwner: extras.activeOwner,
    activeTenant: extras.activeTenant,
    createdAt: new Date(flat.createdAt).toISOString(),
    updatedAt: new Date(flat.updatedAt).toISOString(),
  };
}
