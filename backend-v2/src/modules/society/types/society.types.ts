import type { FlatType, OccupancyStatus } from '../../../config/constants';

export interface SocietySummary {
  id: string;
  name: string;
  code: string;
  address?: string;
  city?: string;
  state?: string;
  pincode?: string;
  contactEmail?: string;
  contactPhone?: string;
  timezone: string;
  currency: string;
  maintenanceDayOfMonth: number;
  annualInterestRateBps: number;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface SocietyConfiguration {
  society: SocietySummary;
  totals: {
    wings: number;
    flats: number;
    activeFlats: number;
    inactiveFlats: number;
    monthlyMaintenanceTotal: number;
    rate4000Count: number;
    rate5000Count: number;
  };
  wings: Array<{
    id: string;
    code: string;
    name: string;
    floors: number;
    flatsPerFloor: number;
    sortOrder: number;
    isActive: boolean;
    flatCount: number;
  }>;
}

export interface WingSummary {
  id: string;
  societyId: string;
  name: string;
  code: string;
  floors: number;
  flatsPerFloor: number;
  sortOrder: number;
  isActive: boolean;
  flatCount: number;
  createdAt: string;
  updatedAt: string;
}

export interface ResidentSummary {
  id: string;
  name: string;
  email: string;
  phone?: string;
  mobileE164?: string;
  role: 'OWNER' | 'TENANT';
}

export interface FlatSummary {
  id: string;
  societyId: string;
  wingId: string;
  wingCode?: string;
  wingName?: string;
  number: string;
  label: string;
  floor: number;
  position: number;
  flatType: FlatType;
  maintenanceRate: number;
  isActive: boolean;
  occupancyStatus: OccupancyStatus;
  parking?: {
    hasParking: boolean;
    slotLabel?: string;
  };
  notes?: string;
  activeOwner?: ResidentSummary;
  activeTenant?: ResidentSummary;
  createdAt: string;
  updatedAt: string;
}

export interface FlatListResult {
  items: FlatSummary[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    totalPages: number;
  };
}

export interface DashboardStats {
  totals: {
    wings: number;
    flats: number;
    activeFlats: number;
    inactiveFlats: number;
    ownerOccupiedFlats: number;
    tenantOccupiedFlats: number;
    vacantFlats: number;
    twoBhkCount: number;
    threeBhkCount: number;
    monthlyMaintenanceTotal: number;
  };
  wings: Array<{
    id: string;
    code: string;
    name: string;
    flatCount: number;
    activeFlats: number;
    inactiveFlats: number;
    ownerOccupiedFlats: number;
    tenantOccupiedFlats: number;
    vacantFlats: number;
    twoBhkCount: number;
    threeBhkCount: number;
    monthlyMaintenanceTotal: number;
  }>;
}
