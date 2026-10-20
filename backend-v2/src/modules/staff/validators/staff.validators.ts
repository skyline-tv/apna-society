import { z } from 'zod';
import { isObjectId } from '../../../utils/object-id';
import { ATTENDANCE_STATUSES } from '../models/staff-attendance.model';
import {
  EMPLOYMENT_STATUSES,
  EMPLOYMENT_TYPES,
  STAFF_CATEGORIES,
} from '../models/staff.model';
import { SHIFT_STATUSES } from '../models/staff-shift.model';

const objectId = z.string().refine(isObjectId, 'Must be a valid ObjectId');
const localDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Must be YYYY-MM-DD');
const hhmm = z.string().regex(/^\d{2}:\d{2}$/, 'Must be HH:mm');
const phone = z.string().trim().min(7).max(32);

export const createStaffSchema = z
  .object({
    fullName: z.string().trim().min(1).max(120),
    phone,
    email: z.string().trim().email().max(254).optional(),
    category: z.enum(STAFF_CATEGORIES),
    employmentType: z.enum(EMPLOYMENT_TYPES),
    joiningDate: localDate,
    address: z.string().trim().max(500).optional(),
    emergencyContactName: z.string().trim().max(120).optional(),
    emergencyContactPhone: phone.optional(),
    notes: z.string().trim().max(4000).optional(),
    linkedUserId: objectId.optional(),
  })
  .strict();

export const updateStaffSchema = z
  .object({
    fullName: z.string().trim().min(1).max(120).optional(),
    phone: phone.optional(),
    email: z.string().trim().email().max(254).optional(),
    category: z.enum(STAFF_CATEGORIES).optional(),
    employmentType: z.enum(EMPLOYMENT_TYPES).optional(),
    address: z.string().trim().max(500).optional(),
    emergencyContactName: z.string().trim().max(120).optional(),
    emergencyContactPhone: phone.optional(),
    notes: z.string().trim().max(4000).optional(),
    linkedUserId: objectId.nullable().optional(),
  })
  .strict()
  .refine((d) => Object.keys(d).length > 0, { message: 'At least one field is required' });

export const staffIdParamSchema = z.object({ staffId: objectId });
export const statusReasonSchema = z
  .object({ reason: z.string().trim().min(1).max(1000).optional() })
  .strict();

export const listStaffQuerySchema = z.object({
  category: z.enum(STAFF_CATEGORIES).optional(),
  employmentType: z.enum(EMPLOYMENT_TYPES).optional(),
  employmentStatus: z.enum(EMPLOYMENT_STATUSES).optional(),
  joiningFrom: localDate.optional(),
  joiningTo: localDate.optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const markAttendanceSchema = z
  .object({
    staffId: objectId,
    localDate: localDate.optional(),
    status: z.enum(ATTENDANCE_STATUSES),
    checkInAt: z.coerce.date().optional(),
    notes: z.string().trim().max(1000).optional(),
  })
  .strict();

export const attendanceIdParamSchema = z.object({ attendanceId: objectId });

export const correctAttendanceSchema = z
  .object({
    status: z.enum(ATTENDANCE_STATUSES).optional(),
    checkInAt: z.coerce.date().nullable().optional(),
    checkOutAt: z.coerce.date().nullable().optional(),
    notes: z.string().trim().max(1000).optional(),
    reason: z.string().trim().min(3).max(1000),
  })
  .strict();

export const listAttendanceQuerySchema = z.object({
  staffId: objectId.optional(),
  localDate: localDate.optional(),
  from: localDate.optional(),
  to: localDate.optional(),
  status: z.enum(ATTENDANCE_STATUSES).optional(),
  category: z.enum(STAFF_CATEGORIES).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const createShiftSchema = z
  .object({
    staffId: objectId,
    shiftDate: localDate,
    startTime: hhmm,
    endTime: hhmm,
    dutyLocation: z.string().trim().max(200).optional(),
    notes: z.string().trim().max(2000).optional(),
  })
  .strict();

export const updateShiftSchema = z
  .object({
    shiftDate: localDate.optional(),
    startTime: hhmm.optional(),
    endTime: hhmm.optional(),
    dutyLocation: z.string().trim().max(200).optional(),
    notes: z.string().trim().max(2000).optional(),
  })
  .strict()
  .refine((d) => Object.keys(d).length > 0, { message: 'At least one field is required' });

export const shiftIdParamSchema = z.object({ shiftId: objectId });

export const listShiftsQuerySchema = z.object({
  staffId: objectId.optional(),
  from: localDate.optional(),
  to: localDate.optional(),
  status: z.enum(SHIFT_STATUSES).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(200).default(50),
});

export const scheduleQuerySchema = z.object({
  from: localDate,
  to: localDate,
});
