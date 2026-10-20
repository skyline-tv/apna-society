import { Router } from 'express';
import { validateBody, validateParams, validateQuery } from '../../../middleware/validate';
import { asyncHandler } from '../../../utils/async-handler';
import {
  attendanceSummaryHandler,
  cancelShiftHandler,
  checkOutAttendanceHandler,
  correctAttendanceHandler,
  createShiftHandler,
  createStaffHandler,
  deactivateStaffHandler,
  getShiftHandler,
  getStaffHandler,
  listAttendanceHandler,
  listShiftsHandler,
  listStaffHandler,
  markAttendanceHandler,
  reactivateStaffHandler,
  scheduleHandler,
  terminateStaffHandler,
  updateShiftHandler,
  updateStaffHandler,
} from '../controllers/staff.controller';
import {
  attendanceIdParamSchema,
  correctAttendanceSchema,
  createShiftSchema,
  createStaffSchema,
  listAttendanceQuerySchema,
  listShiftsQuerySchema,
  listStaffQuerySchema,
  markAttendanceSchema,
  scheduleQuerySchema,
  shiftIdParamSchema,
  staffIdParamSchema,
  statusReasonSchema,
  updateShiftSchema,
  updateStaffSchema,
} from '../validators/staff.validators';

const router = Router();

router.post('/staff', validateBody(createStaffSchema), asyncHandler(createStaffHandler));
router.get('/staff', validateQuery(listStaffQuerySchema), asyncHandler(listStaffHandler));
router.get('/staff/:staffId', validateParams(staffIdParamSchema), asyncHandler(getStaffHandler));
router.patch(
  '/staff/:staffId',
  validateParams(staffIdParamSchema),
  validateBody(updateStaffSchema),
  asyncHandler(updateStaffHandler),
);
router.post(
  '/staff/:staffId/deactivate',
  validateParams(staffIdParamSchema),
  validateBody(statusReasonSchema),
  asyncHandler(deactivateStaffHandler),
);
router.post(
  '/staff/:staffId/terminate',
  validateParams(staffIdParamSchema),
  validateBody(statusReasonSchema),
  asyncHandler(terminateStaffHandler),
);
router.post(
  '/staff/:staffId/reactivate',
  validateParams(staffIdParamSchema),
  asyncHandler(reactivateStaffHandler),
);

router.post(
  '/staff-attendance',
  validateBody(markAttendanceSchema),
  asyncHandler(markAttendanceHandler),
);
router.get(
  '/staff-attendance',
  validateQuery(listAttendanceQuerySchema),
  asyncHandler(listAttendanceHandler),
);
router.get('/staff-attendance/summary', asyncHandler(attendanceSummaryHandler));
router.post(
  '/staff-attendance/:attendanceId/checkout',
  validateParams(attendanceIdParamSchema),
  asyncHandler(checkOutAttendanceHandler),
);
router.post(
  '/staff-attendance/:attendanceId/correct',
  validateParams(attendanceIdParamSchema),
  validateBody(correctAttendanceSchema),
  asyncHandler(correctAttendanceHandler),
);

router.post('/staff-shifts', validateBody(createShiftSchema), asyncHandler(createShiftHandler));
router.get('/staff-shifts', validateQuery(listShiftsQuerySchema), asyncHandler(listShiftsHandler));
router.get(
  '/staff-shifts/schedule',
  validateQuery(scheduleQuerySchema),
  asyncHandler(scheduleHandler),
);
router.get('/staff-shifts/:shiftId', validateParams(shiftIdParamSchema), asyncHandler(getShiftHandler));
router.patch(
  '/staff-shifts/:shiftId',
  validateParams(shiftIdParamSchema),
  validateBody(updateShiftSchema),
  asyncHandler(updateShiftHandler),
);
router.post(
  '/staff-shifts/:shiftId/cancel',
  validateParams(shiftIdParamSchema),
  validateBody(statusReasonSchema),
  asyncHandler(cancelShiftHandler),
);

export default router;
