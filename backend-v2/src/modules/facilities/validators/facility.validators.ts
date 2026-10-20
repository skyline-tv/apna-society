import { z } from 'zod';
import { isObjectId } from '../../../utils/object-id';
import { BOOKING_STATUSES } from '../models/facility-booking.model';
import { FACILITY_CATEGORIES, WEEKDAYS } from '../models/facility.model';

const objectId = z.string().refine(isObjectId, 'Must be a valid ObjectId');
const localDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Must be YYYY-MM-DD');
const hhmm = z.string().regex(/^\d{2}:\d{2}$/, 'Must be HH:mm');

export const createFacilitySchema = z
  .object({
    name: z.string().trim().min(1).max(120),
    description: z.string().trim().max(2000).optional(),
    category: z.enum(FACILITY_CATEGORIES),
    location: z.string().trim().max(200).optional(),
    capacity: z.coerce.number().int().min(1).max(10_000),
    bookingRequired: z.boolean().optional(),
    requiresApproval: z.boolean().optional(),
    maxBookingDurationMinutes: z.coerce.number().int().min(15).max(24 * 60),
    openingTime: hhmm,
    closingTime: hhmm,
    availableDays: z.array(z.enum(WEEKDAYS)).min(1),
    bookingFeePaise: z.coerce.number().int().min(0).optional(),
  })
  .strict();

export const updateFacilitySchema = createFacilitySchema.partial().refine(
  (d) => Object.keys(d).length > 0,
  { message: 'At least one field is required' },
);

export const facilityIdParamSchema = z.object({ facilityId: objectId });
export const setFacilityActiveSchema = z.object({ isActive: z.boolean() }).strict();

export const listFacilitiesQuerySchema = z.object({
  isActive: z
    .enum(['true', 'false'])
    .optional()
    .transform((v) => (v === undefined ? undefined : v === 'true')),
  category: z.enum(FACILITY_CATEGORIES).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const availabilityQuerySchema = z.object({
  date: localDate,
});

export const createBookingSchema = z
  .object({
    flatId: objectId,
    bookingDate: localDate,
    startTime: hhmm,
    endTime: hhmm,
  })
  .strict();

export const bookingIdParamSchema = z.object({ bookingId: objectId });

export const listBookingsQuerySchema = z.object({
  status: z.enum(BOOKING_STATUSES).optional(),
  facilityId: objectId.optional(),
  flatId: objectId.optional(),
  from: localDate.optional(),
  to: localDate.optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const approveBookingSchema = z
  .object({ adminNotes: z.string().trim().max(4000).optional() })
  .strict();

export const rejectBookingSchema = z
  .object({ reason: z.string().trim().min(3).max(1000) })
  .strict();

export const cancelBookingSchema = z
  .object({ reason: z.string().trim().min(1).max(1000).optional() })
  .strict();
